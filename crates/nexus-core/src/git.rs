use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct GitStatus {
    pub exists: bool,
    pub branch: String,
    pub dirty: bool,
    pub summary: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceRepo {
    pub name: String,
    pub path: String,
    pub is_git: bool,
    pub branch: String,
    pub dirty: bool,
    pub summary: String,
}

pub fn scan_source_repos(source_repos_root: &str) -> Result<Vec<SourceRepo>, String> {
    let root = expand_user_path(source_repos_root);
    if !root.exists() {
        return Ok(Vec::new());
    }

    let mut repos = Vec::new();
    let entries = fs::read_dir(&root).map_err(|error| error.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if !path.is_dir()
            || name.starts_with('.')
            || matches!(name.as_str(), "node_modules" | "target" | "dist")
        {
            continue;
        }
        let status = git_status(&path);
        let is_git = path.join(".git").exists();
        repos.push(SourceRepo {
            name,
            path: path.to_string_lossy().to_string(),
            is_git,
            branch: status.branch,
            dirty: status.dirty,
            summary: status.summary,
        });
    }
    repos.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(repos)
}

pub fn git_status(path: impl AsRef<Path>) -> GitStatus {
    let path = path.as_ref();
    if !path.exists() {
        return GitStatus {
            exists: false,
            branch: "未创建".to_string(),
            dirty: false,
            summary: "未创建".to_string(),
        };
    }
    if !path.join(".git").exists() {
        return GitStatus {
            exists: true,
            branch: "非 git worktree".to_string(),
            dirty: true,
            summary: "目录存在但不是 git worktree".to_string(),
        };
    }
    let output = Command::new("git")
        .args([
            "-C",
            &path.to_string_lossy(),
            "status",
            "--short",
            "--branch",
        ])
        .output();
    match output {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let lines = stdout
                .lines()
                .map(str::trim)
                .filter(|line| !line.is_empty())
                .collect::<Vec<_>>();
            let branch = lines
                .first()
                .map(|line| line.replace("## ", ""))
                .unwrap_or_else(|| "未知".to_string());
            let dirty = lines.len() > 1;
            GitStatus {
                exists: true,
                branch,
                dirty,
                summary: if dirty {
                    "有未提交改动"
                } else {
                    "干净"
                }
                .to_string(),
            }
        }
        Ok(output) => GitStatus {
            exists: true,
            branch: "检查失败".to_string(),
            dirty: true,
            summary: String::from_utf8_lossy(&output.stderr).trim().to_string(),
        },
        Err(error) => GitStatus {
            exists: true,
            branch: "检查失败".to_string(),
            dirty: true,
            summary: error.to_string(),
        },
    }
}

pub fn normalize_git_branch(value: &str) -> String {
    let trimmed = value.trim();
    let status_branch = trimmed.trim_start_matches("## ");
    let branch = status_branch
        .strip_prefix("No commits yet on ")
        .unwrap_or(status_branch);
    branch
        .split("...")
        .next()
        .unwrap_or(branch)
        .split(' ')
        .next()
        .unwrap_or(branch)
        .trim()
        .to_string()
}

pub fn target_branch_exists(path: impl AsRef<Path>, target_branch: &str) -> Result<bool, String> {
    let path = path.as_ref();
    if !path.exists() || !path.join(".git").exists() {
        return Ok(false);
    }

    let target = normalize_branch_ref_target(target_branch);
    if !target_branch_confirmed(&target) {
        return Ok(true);
    }

    let status = git_status(path);
    if normalize_branch_ref_target(&status.branch) == target {
        return Ok(true);
    }

    let output = Command::new("git")
        .args(["-C", &path.to_string_lossy(), "show-ref"])
        .output()
        .map_err(|error| error.to_string())?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    if stdout
        .lines()
        .filter_map(|line| line.split_whitespace().last())
        .any(|refname| branch_ref_matches_target(refname, &target))
    {
        return Ok(true);
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if output.status.success() || (stdout.trim().is_empty() && stderr.is_empty()) {
        return Ok(false);
    }

    Err(if stderr.is_empty() {
        format!("git show-ref exited with {}", output.status)
    } else {
        stderr
    })
}

fn normalize_branch_ref_target(value: &str) -> String {
    normalize_git_branch(value)
        .trim_start_matches("origin/")
        .to_string()
}

fn branch_ref_matches_target(refname: &str, target_branch: &str) -> bool {
    if refname == format!("refs/heads/{target_branch}") {
        return true;
    }
    let Some(remote_ref) = refname.strip_prefix("refs/remotes/") else {
        return false;
    };
    let Some((_, branch)) = remote_ref.split_once('/') else {
        return false;
    };
    branch == target_branch
}

pub fn target_branch_confirmed(value: &str) -> bool {
    let branch = normalize_git_branch(value);
    !branch.is_empty() && !branch.contains("待确认") && branch != "<target-branch>"
}

pub fn expand_user_path(value: &str) -> PathBuf {
    if value == "~" {
        return std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(value));
    }
    if let Some(rest) = value.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_git_branch_strips_status_tracking_suffixes() {
        assert_eq!(
            normalize_git_branch("## chen/demo...origin/chen/demo [ahead 1]"),
            "chen/demo"
        );
        assert_eq!(
            normalize_git_branch("## No commits yet on chen/demo"),
            "chen/demo"
        );
        assert_eq!(normalize_git_branch("main...origin/main"), "main");
        assert_eq!(normalize_git_branch(" feature/demo "), "feature/demo");
    }

    #[test]
    fn target_branch_confirmed_rejects_placeholders() {
        assert!(target_branch_confirmed("chen/demo"));
        assert!(!target_branch_confirmed("待确认"));
        assert!(!target_branch_confirmed("<target-branch>"));
        assert!(!target_branch_confirmed(""));
    }

    #[test]
    fn branch_ref_matches_local_and_remote_targets() {
        assert!(branch_ref_matches_target(
            "refs/heads/chen/demo",
            "chen/demo"
        ));
        assert!(branch_ref_matches_target(
            "refs/remotes/origin/chen/demo",
            "chen/demo"
        ));
        assert!(branch_ref_matches_target(
            "refs/remotes/upstream/feature/pricing",
            "feature/pricing"
        ));
        assert!(!branch_ref_matches_target(
            "refs/heads/feature/other",
            "feature/pricing"
        ));
    }

    #[test]
    fn git_status_reports_missing_paths_without_shelling_out() {
        let missing =
            std::env::temp_dir().join(format!("nexus-core-missing-{}", std::process::id()));
        let status = git_status(&missing);
        assert!(!status.exists);
        assert_eq!(status.branch, "未创建");
        assert!(!status.dirty);
    }

    #[test]
    fn scan_source_repos_sorts_and_filters_directories() {
        let root =
            std::env::temp_dir().join(format!("nexus-core-source-repos-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("order")).unwrap();
        fs::create_dir_all(root.join("commodity")).unwrap();
        fs::create_dir_all(root.join(".hidden")).unwrap();
        fs::create_dir_all(root.join("dist")).unwrap();
        fs::write(root.join("README.md"), "not a repo").unwrap();

        let repos = scan_source_repos(&root.to_string_lossy()).unwrap();
        let names = repos
            .iter()
            .map(|repo| repo.name.as_str())
            .collect::<Vec<_>>();

        assert_eq!(names, vec!["commodity", "order"]);
        assert!(repos.iter().all(|repo| !repo.is_git));
        assert!(repos.iter().all(|repo| repo.dirty));

        fs::remove_dir_all(root).unwrap();
    }
}
