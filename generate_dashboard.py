#!/usr/bin/env python3
"""Generate a static dashboard for ks_project demand workspaces."""

import datetime as dt
import html
import json
import os
import re
import subprocess
from pathlib import Path


DEFAULT_WORKSPACES_ROOT = Path.home() / "ks_project" / "workspaces"
DASHBOARD_DIR = Path(__file__).resolve().parent
SETTINGS_FILE = DASHBOARD_DIR / "config" / "nexus-settings.json"


def load_settings():
    if not SETTINGS_FILE.exists():
        return {}
    try:
        return json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


SETTINGS = load_settings()
WORKSPACES_ROOT = Path(os.environ.get("NEXUS_WORKSPACES_ROOT") or SETTINGS.get("workspacesRoot") or DEFAULT_WORKSPACES_ROOT)
SOURCE_REPOS_ROOT = Path(os.environ.get("NEXUS_SOURCE_REPOS_ROOT") or SETTINGS.get("sourceReposRoot") or Path.home() / "ks_project" / "source-repos")
DOCS_ROOT = Path(os.environ.get("NEXUS_DOCS_ROOT") or SETTINGS.get("docsRoot") or Path.home() / "ks_project" / "docs")
OUTPUT = DASHBOARD_DIR / "index.html"
DATA_OUTPUT = DASHBOARD_DIR / "src" / "data" / "workspaces.json"
PUBLIC_DATA_OUTPUT = DASHBOARD_DIR / "public" / "data" / "workspaces.json"


def read_text(path):
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="ignore")


def clean(value):
    return value.replace("`", "").strip()


def extract_bullet_value(text, label):
    pattern = re.compile(rf"^- {re.escape(label)}[:：]\s*(.+)$", re.MULTILINE)
    match = pattern.search(text)
    return clean(match.group(1)) if match else ""


def section(text, heading):
    marker = f"## {heading}"
    start = text.find(marker)
    if start < 0:
        return ""
    start += len(marker)
    match = re.search(r"\n##\s+", text[start:])
    end = start + match.start() if match else len(text)
    return text[start:end]


def table_rows(text):
    rows = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|") or "---" in stripped:
            continue
        cells = [clean(cell) for cell in stripped.strip("|").split("|")]
        if cells and cells[0] not in {"服务", "任务", "需求", "场景"}:
            rows.append(cells)
    return rows


def service_names_from(rows):
    names = []
    for row in rows:
        if row and row[0] not in {"待确认", "待补充", ""}:
            names.append(row[0])
    return names


def run_git_status(path):
    if not path.exists():
        return {"exists": False, "branch": "未创建", "dirty": False, "summary": "未创建"}
    git_marker = path / ".git"
    if not git_marker.exists():
        return {"exists": True, "branch": "非 git worktree", "dirty": True, "summary": "目录存在但不是 git worktree"}
    result = subprocess.run(
        ["git", "-C", str(path), "status", "--short", "--branch"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return {"exists": True, "branch": "检查失败", "dirty": True, "summary": result.stderr.strip() or "检查失败"}
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    branch = lines[0].replace("## ", "") if lines else "未知"
    dirty = len(lines) > 1
    summary = "有未提交改动" if dirty else "干净"
    return {"exists": True, "branch": branch, "dirty": dirty, "summary": summary}


def count_tasks(rows):
    counts = {"done": 0, "doing": 0, "todo": 0, "blocked": 0}
    for row in rows:
        joined = " ".join(row)
        if "阻塞" in joined or "blocked" in joined.lower():
            counts["blocked"] += 1
        elif any(word in joined for word in ["已完成", "已确认", "已创建", "完成"]):
            counts["done"] += 1
        elif any(word in joined for word in ["持续进行", "进行中", "doing"]):
            counts["doing"] += 1
        else:
            counts["todo"] += 1
    return counts


def workspace_dirs():
    return sorted(
        path
        for path in WORKSPACES_ROOT.iterdir()
        if path.is_dir() and path.name != "dashboard" and not path.name.startswith(".")
    )


def collect_workspace(path):
    workspace_md = read_text(path / "workspace.md")
    services_md = read_text(path / "services.md")
    branches_md = read_text(path / "branches.md")
    tasks_md = read_text(path / "tasks.md")
    decisions_md = read_text(path / "decisions.md")

    name = extract_bullet_value(workspace_md, "需求名称") or path.name
    state = extract_bullet_value(workspace_md, "当前状态") or "unknown"
    target_branch = (
        extract_bullet_value(workspace_md, "目标分支")
        or extract_bullet_value(workspace_md, "建议目标分支")
        or "待确认"
    )
    source_root = extract_bullet_value(workspace_md, "源仓库集合") or str(SOURCE_REPOS_ROOT)

    confirmed_rows = table_rows(section(services_md, "已确认相关")) or table_rows(section(services_md, "初步服务范围"))
    candidate_rows = table_rows(section(services_md, "待验证范围"))
    confirmed = service_names_from(confirmed_rows)
    candidates = [name for name in service_names_from(candidate_rows) if name not in confirmed]

    task_rows = table_rows(tasks_md)
    decision_rows = table_rows(decisions_md)
    task_counts = count_tasks(task_rows)

    git_rows = []
    for service in confirmed:
        worktree_path = path / "repos" / service
        source_path = Path(source_root) / service
        worktree = run_git_status(worktree_path)
        source = run_git_status(source_path)
        git_rows.append(
            {
                "service": service,
                "worktreePath": str(worktree_path),
                "sourcePath": str(source_path),
                "worktree": worktree,
                "source": source,
            }
        )

    risks = []
    if "待确认" in target_branch:
        risks.append("目标分支未确认")
    if not confirmed:
        risks.append("服务范围未确认")
    missing_worktrees = [row["service"] for row in git_rows if not row["worktree"]["exists"]]
    if missing_worktrees:
        risks.append("worktree 未创建: " + ", ".join(missing_worktrees))
    dirty_worktrees = [row["service"] for row in git_rows if row["worktree"]["dirty"]]
    if dirty_worktrees:
        risks.append("worktree 有未提交改动: " + ", ".join(dirty_worktrees))
    if not (path / "交付记录.md").exists():
        risks.append("缺少交付记录")
    if not (path / "sql").exists():
        risks.append("缺少 SQL 目录")

    links = {
        "folder": str(path),
        "workspace": str(path / "workspace.md"),
        "status": str(path / "STATUS.md"),
        "services": str(path / "services.md"),
        "branches": str(path / "branches.md"),
        "tasks": str(path / "tasks.md"),
        "delivery": str(path / "交付记录.md"),
        "handoff": str(path / "handoff.md"),
        "sql": str(path / "sql"),
    }

    return {
        "name": name,
        "folder": path.name,
        "path": str(path),
        "state": state,
        "targetBranch": target_branch,
        "sourceRoot": source_root,
        "confirmedServices": confirmed,
        "candidateServices": candidates,
        "taskCounts": task_counts,
        "decisionCount": len(decision_rows),
        "gitRows": git_rows,
        "risks": risks,
        "riskCount": len(risks),
        "updated": dt.date.today().isoformat(),
        "links": links,
        "worktreeCommand": (
            "python3 /path/to/ks-project-demand-workspace/scripts/create_worktrees.py "
            f"--workspace {path} --services {','.join(confirmed) or '<services>'} --branch <target-branch>"
        ),
    }


def file_url(path):
    return "file://" + Path(path).as_posix()


def render_dashboard(workspaces):
    data = json.dumps(workspaces, ensure_ascii=False)
    generated = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    escaped_root = html.escape(str(WORKSPACES_ROOT))
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>KS Project Control</title>
  <style>
    :root {{
      --ink: #171a1d;
      --soft-ink: #3e454d;
      --muted: #717982;
      --line: #d6d1c6;
      --paper: #efebe2;
      --panel: #fffefa;
      --panel-2: #f7f3eb;
      --green: #1e7358;
      --blue: #305d8c;
      --amber: #aa6b13;
      --red: #a64235;
      --violet: #6a4c93;
      --shadow: 0 10px 30px rgba(38, 35, 28, .10);
      --radius: 8px;
    }}

    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      color: var(--ink);
      background:
        linear-gradient(90deg, rgba(23,26,29,.045) 1px, transparent 1px),
        linear-gradient(180deg, rgba(23,26,29,.035) 1px, transparent 1px),
        var(--paper);
      background-size: 32px 32px;
      font-family: "Avenir Next", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
      letter-spacing: 0;
    }}

    .layout {{
      display: grid;
      grid-template-columns: 260px minmax(0, 1fr);
      min-height: 100vh;
    }}

    aside {{
      border-right: 2px solid var(--ink);
      background: #e8dfd0;
      padding: 22px 18px;
      position: sticky;
      top: 0;
      height: 100vh;
      overflow: auto;
    }}

    .brand {{
      font-family: Georgia, "Songti SC", serif;
      font-size: 30px;
      line-height: 1;
      margin: 0 0 12px;
    }}

    .side-note {{
      color: var(--soft-ink);
      font-size: 13px;
      line-height: 1.55;
      margin-bottom: 22px;
    }}

    .side-block {{
      border-top: 1px solid rgba(23,26,29,.22);
      padding-top: 14px;
      margin-top: 14px;
    }}

    .side-block b {{
      display: block;
      font-size: 12px;
      text-transform: uppercase;
      margin-bottom: 8px;
    }}

    .side-block a, .side-block button {{
      display: block;
      width: 100%;
      text-align: left;
      border: 1px solid var(--ink);
      background: var(--panel);
      color: var(--ink);
      text-decoration: none;
      border-radius: 6px;
      padding: 9px 10px;
      margin-bottom: 8px;
      font: inherit;
      font-size: 13px;
      cursor: pointer;
    }}

    main {{
      padding: 22px;
      max-width: 1520px;
      width: 100%;
    }}

    header {{
      display: grid;
      grid-template-columns: minmax(320px, 1fr) auto;
      gap: 18px;
      align-items: end;
      border-bottom: 2px solid var(--ink);
      padding-bottom: 16px;
    }}

    h1 {{
      margin: 0;
      font-size: clamp(28px, 4vw, 52px);
      font-family: Georgia, "Songti SC", serif;
      line-height: .96;
    }}

    .sub {{
      color: var(--muted);
      font-size: 13px;
      margin-top: 8px;
      overflow-wrap: anywhere;
    }}

    .stamp {{
      background: var(--panel);
      border: 2px solid var(--ink);
      padding: 10px 12px;
      min-width: 250px;
      box-shadow: 5px 5px 0 rgba(23,26,29,.16);
      font-size: 13px;
    }}

    .stamp b {{ display: block; font-size: 12px; text-transform: uppercase; }}
    .stamp label {{ display: flex; gap: 8px; align-items: center; margin-top: 8px; color: var(--soft-ink); }}

    .metrics {{
      display: grid;
      grid-template-columns: repeat(5, minmax(130px, 1fr));
      gap: 10px;
      margin: 16px 0;
    }}

    .metric {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-left: 5px solid var(--ink);
      padding: 12px;
      min-height: 72px;
    }}

    .metric strong {{ display: block; font-size: 25px; line-height: 1; }}
    .metric span {{ color: var(--muted); font-size: 12px; }}

    .toolbar {{
      display: grid;
      grid-template-columns: 1fr 170px 180px;
      gap: 10px;
      margin: 18px 0 12px;
    }}

    input, select {{
      height: 38px;
      width: 100%;
      border: 1px solid var(--line);
      background: var(--panel);
      color: var(--ink);
      border-radius: 6px;
      padding: 0 11px;
      font: inherit;
    }}

    .workspace {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      margin-bottom: 14px;
      overflow: hidden;
    }}

    .workspace-head {{
      display: grid;
      grid-template-columns: minmax(260px, 1fr) auto;
      gap: 12px;
      padding: 14px 16px;
      background: var(--panel-2);
      border-bottom: 1px solid var(--line);
    }}

    h2 {{ margin: 0; font-size: 21px; line-height: 1.2; overflow-wrap: anywhere; }}
    .folder {{ color: var(--muted); font-size: 12px; margin-top: 5px; }}

    .badge {{
      display: inline-flex;
      align-items: center;
      height: 25px;
      border: 1px solid currentColor;
      border-radius: 999px;
      padding: 0 9px;
      font-size: 12px;
      color: var(--blue);
      white-space: nowrap;
    }}
    .badge.risk {{ color: var(--red); }}
    .badge.ok {{ color: var(--green); }}
    .badge.todo {{ color: var(--amber); }}

    .workspace-body {{
      display: grid;
      grid-template-columns: minmax(250px, .85fr) minmax(430px, 1.35fr);
      gap: 16px;
      padding: 14px 16px 16px;
    }}

    .kv {{
      display: grid;
      grid-template-columns: 76px 1fr;
      gap: 8px;
      font-size: 13px;
      margin-bottom: 9px;
    }}
    .key {{ color: var(--muted); }}
    .mono {{ font-family: "SFMono-Regular", Menlo, Consolas, monospace; overflow-wrap: anywhere; font-size: 12px; }}

    .chips {{ display: flex; flex-wrap: wrap; gap: 6px; }}
    .chip {{
      border: 1px solid var(--line);
      background: #fbfaf5;
      border-radius: 6px;
      padding: 4px 7px;
      font-size: 12px;
    }}
    .chip.candidate {{ color: var(--violet); border-color: rgba(106,76,147,.35); }}

    .taskbar {{
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 7px;
      margin: 12px 0;
    }}
    .taskbox {{
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 8px;
      background: #fff;
    }}
    .taskbox b {{ display: block; font-size: 16px; }}
    .taskbox span {{ color: var(--muted); font-size: 11px; }}

    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
      background: #fff;
      border: 1px solid var(--line);
      border-radius: 6px;
      overflow: hidden;
    }}
    th, td {{
      border-bottom: 1px solid var(--line);
      padding: 8px;
      text-align: left;
      vertical-align: top;
    }}
    th {{ background: #f2eee5; color: var(--soft-ink); font-weight: 700; }}
    tr:last-child td {{ border-bottom: 0; }}

    .risk-list {{
      display: grid;
      gap: 6px;
      margin-top: 10px;
    }}
    .risk-item {{
      border-left: 4px solid var(--red);
      background: #fff5f2;
      padding: 7px 9px;
      font-size: 12px;
      color: var(--red);
      border-radius: 4px;
    }}

    .links {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 12px;
      padding-top: 12px;
      border-top: 1px solid var(--line);
    }}
    .links a {{
      color: var(--blue);
      text-decoration: none;
      border-bottom: 1px solid rgba(48,93,140,.35);
      font-size: 13px;
    }}

    .cmd {{
      margin-top: 10px;
      background: #202326;
      color: #f4f0e8;
      border-radius: 6px;
      padding: 9px;
      font-size: 11px;
      overflow-x: auto;
    }}

    .empty {{
      background: var(--panel);
      border: 1px dashed var(--muted);
      padding: 28px;
      text-align: center;
      color: var(--muted);
      border-radius: var(--radius);
    }}

    @media (max-width: 980px) {{
      .layout {{ grid-template-columns: 1fr; }}
      aside {{ position: relative; height: auto; border-right: 0; border-bottom: 2px solid var(--ink); }}
      header, .workspace-head, .workspace-body, .toolbar {{ grid-template-columns: 1fr; }}
      .metrics {{ grid-template-columns: repeat(2, 1fr); }}
    }}
  </style>
</head>
<body>
  <div class="layout">
    <aside>
      <h1 class="brand">KS Control</h1>
      <div class="side-note">本地需求工作台。Markdown 是事实来源，watcher 负责重生成页面。</div>
      <div class="side-block">
        <b>入口</b>
        <a href="{file_url(WORKSPACES_ROOT / 'INDEX.md')}">INDEX.md</a>
        <a href="{file_url(WORKSPACES_ROOT)}">工作区目录</a>
      </div>
      <div class="side-block">
        <b>路径规则</b>
        <div class="side-note">看代码：source-repos。开发：workspaces/&lt;需求&gt;/repos。SQL：工作区 sql/。</div>
      </div>
    </aside>

    <main>
      <header>
        <div>
          <h1>Workspaces</h1>
          <div class="sub">读取 {escaped_root}，生成时间 {generated}</div>
        </div>
        <div class="stamp">
          <b>Auto refresh</b>
          <span id="refreshText">30s</span>
          <label><input id="autoRefresh" type="checkbox"> 自动刷新页面</label>
        </div>
      </header>

      <section class="metrics" id="metrics"></section>

      <section class="toolbar">
        <input id="search" placeholder="搜索需求、服务、分支或路径">
        <select id="stateFilter"><option value="">全部状态</option></select>
        <select id="riskFilter">
          <option value="">全部风险</option>
          <option value="risk">仅看有风险</option>
          <option value="clean">仅看无风险</option>
        </select>
      </section>

      <section id="list"></section>
    </main>
  </div>

  <script>
    const DATA = {data};
    const stateLabel = {{
      analyzing: "分析中",
      developing: "开发中",
      testing: "验证中",
      delivered: "已交付",
      archived: "已归档",
      unknown: "未知"
    }};
    const fileUrl = path => "file://" + path;

    function metric(label, value, tone = "") {{
      return `<div class="metric"><strong>${{value}}</strong><span>${{label}}</span></div>`;
    }}

    function renderMetrics(items) {{
      const serviceCount = new Set(items.flatMap(x => x.confirmedServices)).size;
      const riskCount = items.reduce((sum, x) => sum + x.riskCount, 0);
      const missing = items.filter(x => x.risks.some(r => r.includes("worktree"))).length;
      document.getElementById("metrics").innerHTML = [
        metric("工作区", items.length),
        metric("确认服务", serviceCount),
        metric("风险项", riskCount),
        metric("待建 worktree", missing),
        metric("活跃需求", items.filter(x => x.state !== "archived").length)
      ].join("");
    }}

    function chips(items, className = "") {{
      return items.length
        ? items.map(x => `<span class="chip ${{className}}">${{x}}</span>`).join("")
        : `<span class="chip">待确认</span>`;
    }}

    function gitTable(rows) {{
      if (!rows.length) return `<div class="empty">尚未确认服务</div>`;
      return `<table>
        <thead><tr><th>服务</th><th>worktree</th><th>源仓库</th></tr></thead>
        <tbody>${{rows.map(row => `<tr>
          <td><b>${{row.service}}</b></td>
          <td><span class="mono">${{row.worktree.branch}}</span><br>${{row.worktree.summary}}</td>
          <td><span class="mono">${{row.source.branch}}</span><br>${{row.source.summary}}</td>
        </tr>`).join("")}}</tbody>
      </table>`;
    }}

    function workspace(item) {{
      const riskBadge = item.riskCount
        ? `<span class="badge risk">${{item.riskCount}} 风险</span>`
        : `<span class="badge ok">无风险</span>`;
      const risks = item.risks.length
        ? `<div class="risk-list">${{item.risks.map(r => `<div class="risk-item">${{r}}</div>`).join("")}}</div>`
        : "";
      return `<article class="workspace">
        <div class="workspace-head">
          <div>
            <h2>${{item.name}}</h2>
            <div class="folder mono">${{item.folder}}</div>
          </div>
          <div class="chips">
            <span class="badge">${{stateLabel[item.state] || item.state}}</span>
            ${{riskBadge}}
          </div>
        </div>
        <div class="workspace-body">
          <section>
            <div class="kv"><div class="key">目标分支</div><div class="mono">${{item.targetBranch}}</div></div>
            <div class="kv"><div class="key">确认服务</div><div class="chips">${{chips(item.confirmedServices)}}</div></div>
            <div class="kv"><div class="key">候选服务</div><div class="chips">${{chips(item.candidateServices, "candidate")}}</div></div>
            <div class="kv"><div class="key">源仓库</div><div class="mono">${{item.sourceRoot}}</div></div>
            <div class="taskbar">
              <div class="taskbox"><b>${{item.taskCounts.done}}</b><span>完成</span></div>
              <div class="taskbox"><b>${{item.taskCounts.doing}}</b><span>进行</span></div>
              <div class="taskbox"><b>${{item.taskCounts.todo}}</b><span>待办</span></div>
              <div class="taskbox"><b>${{item.taskCounts.blocked}}</b><span>阻塞</span></div>
            </div>
            ${{risks}}
            <div class="links">
              <a href="${{fileUrl(item.links.folder)}}">目录</a>
              <a href="${{fileUrl(item.links.status)}}">状态</a>
              <a href="${{fileUrl(item.links.services)}}">服务</a>
              <a href="${{fileUrl(item.links.branches)}}">分支</a>
              <a href="${{fileUrl(item.links.tasks)}}">任务</a>
              <a href="${{fileUrl(item.links.delivery)}}">交付</a>
              <a href="${{fileUrl(item.links.sql)}}">SQL</a>
            </div>
          </section>
          <section>
            ${{gitTable(item.gitRows)}}
            <div class="cmd mono">${{item.worktreeCommand}}</div>
          </section>
        </div>
      </article>`;
    }}

    function render() {{
      const q = document.getElementById("search").value.trim().toLowerCase();
      const state = document.getElementById("stateFilter").value;
      const risk = document.getElementById("riskFilter").value;
      const filtered = DATA.filter(item => {{
        const haystack = [item.name, item.folder, item.targetBranch, item.sourceRoot, item.path, ...item.confirmedServices, ...item.candidateServices].join(" ").toLowerCase();
        const stateOk = !state || item.state === state;
        const riskOk = !risk || (risk === "risk" ? item.riskCount > 0 : item.riskCount === 0);
        return stateOk && riskOk && (!q || haystack.includes(q));
      }});
      document.getElementById("list").innerHTML = filtered.length ? filtered.map(workspace).join("") : `<div class="empty">没有匹配的工作区</div>`;
    }}

    function init() {{
      const stateSelect = document.getElementById("stateFilter");
      [...new Set(DATA.map(x => x.state))].sort().forEach(state => {{
        const option = document.createElement("option");
        option.value = state;
        option.textContent = stateLabel[state] || state;
        stateSelect.appendChild(option);
      }});
      ["search", "stateFilter", "riskFilter"].forEach(id => document.getElementById(id).addEventListener("input", render));
      renderMetrics(DATA);
      render();

      const refresh = document.getElementById("autoRefresh");
      refresh.checked = localStorage.getItem("ks-dashboard-auto-refresh") === "1";
      refresh.addEventListener("change", () => localStorage.setItem("ks-dashboard-auto-refresh", refresh.checked ? "1" : "0"));
      setInterval(() => {{
        if (refresh.checked && !document.hidden) location.reload();
      }}, 30000);
    }}

    init();
  </script>
</body>
</html>
"""


def main():
    DASHBOARD_DIR.mkdir(parents=True, exist_ok=True)
    DATA_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    PUBLIC_DATA_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    workspaces = [collect_workspace(path) for path in workspace_dirs()]
    payload = (
        json.dumps(
            {
                "generatedAt": dt.datetime.now().isoformat(timespec="seconds"),
                "workspacesRoot": str(WORKSPACES_ROOT),
                "sourceReposRoot": str(SOURCE_REPOS_ROOT),
                "docsRoot": str(DOCS_ROOT),
                "workspaces": workspaces,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    DATA_OUTPUT.write_text(payload, encoding="utf-8")
    PUBLIC_DATA_OUTPUT.write_text(payload, encoding="utf-8")
    print(DATA_OUTPUT)
    print(PUBLIC_DATA_OUTPUT)


if __name__ == "__main__":
    main()
