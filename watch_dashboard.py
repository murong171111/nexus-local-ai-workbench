#!/usr/bin/env python3
"""Watch local workspaces and regenerate the dashboard JSON for web development."""

import argparse
import os
import subprocess
import time
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent
WORKSPACES_ROOT = Path(os.environ.get("NEXUS_WORKSPACES_ROOT") or Path.home() / "ks_project" / "workspaces")
GENERATOR = PROJECT_DIR / "generate_dashboard.py"
WATCH_EXTENSIONS = {".md", ".sql"}
WATCH_NAMES = {"AGENTS.md"}
IGNORE_DIRS = {"dashboard", "repos", ".git", "target", ".idea"}


def iter_watch_files(root):
    for path in root.rglob("*"):
        if any(part in IGNORE_DIRS for part in path.parts):
            continue
        if path.is_file() and (path.suffix in WATCH_EXTENSIONS or path.name in WATCH_NAMES):
            yield path


def snapshot(root):
    result = {}
    for path in iter_watch_files(root):
        try:
            stat = path.stat()
        except FileNotFoundError:
            continue
        result[str(path)] = (stat.st_mtime_ns, stat.st_size)
    return result


def regenerate():
    completed = subprocess.run(
        ["python3", str(GENERATOR)],
        text=True,
        capture_output=True,
        check=False,
    )
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    if completed.returncode == 0:
        print(f"[{stamp}] regenerated {completed.stdout.strip()}")
    else:
        print(f"[{stamp}] regenerate failed")
        if completed.stdout:
            print(completed.stdout)
        if completed.stderr:
            print(completed.stderr)


def main():
    parser = argparse.ArgumentParser(description="Watch workspace docs and regenerate dashboard")
    parser.add_argument("--interval", type=float, default=2.0, help="Polling interval in seconds")
    parser.add_argument("--once", action="store_true", help="Generate once and exit")
    args = parser.parse_args()

    regenerate()
    if args.once:
        return

    print(f"Watching {WORKSPACES_ROOT} every {args.interval:g}s. Press Ctrl+C to stop.")
    previous = snapshot(WORKSPACES_ROOT)
    try:
        while True:
            time.sleep(args.interval)
            current = snapshot(WORKSPACES_ROOT)
            if current != previous:
                regenerate()
                previous = current
    except KeyboardInterrupt:
        print("Stopped.")


if __name__ == "__main__":
    main()
