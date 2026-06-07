use crate::expand_user_path;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

const DEMAND_INTAKE_DIR: &str = "需求";
const DEMAND_INTAKE_FILES: [(&str, &str, &str); 5] = [
    ("requirement", "需求确认卡", "requirement.md"),
    ("questions", "待确认问题", "questions.md"),
    ("scope", "开发范围", "scope.md"),
    ("tasks", "需求列表", "tasks.md"),
    ("delivery", "需求交付", "delivery.md"),
];

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DemandIntakeFileStatus {
    pub key: String,
    pub label: String,
    pub filename: String,
    pub path: String,
    pub exists: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DemandIntakeStatus {
    pub directory_path: String,
    pub exists: bool,
    pub ready: bool,
    pub missing_count: usize,
    pub files: Vec<DemandIntakeFileStatus>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeDemandIntakeRequest {
    pub workspace_path: String,
    #[serde(default)]
    pub demand_name: String,
    #[serde(default)]
    pub lanhu_link: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub confirmed: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeDemandIntakeResponse {
    pub status: DemandIntakeStatus,
    pub created_files: Vec<String>,
}

pub fn read_demand_intake_status(workspace_path: &str) -> Result<DemandIntakeStatus, String> {
    let workspace = checked_workspace_path(workspace_path)?;
    Ok(demand_intake_status_for_workspace(&workspace))
}

pub fn initialize_demand_intake(
    request: InitializeDemandIntakeRequest,
) -> Result<InitializeDemandIntakeResponse, String> {
    if !request.confirmed {
        return Err("demand intake initialization requires explicit confirmation".to_string());
    }

    let workspace = checked_workspace_path(&request.workspace_path)?;
    let demand_dir = workspace.join(DEMAND_INTAKE_DIR);
    if demand_dir.exists() && !demand_dir.is_dir() {
        return Err(format!(
            "demand intake path exists but is not a directory: {}",
            demand_dir.display()
        ));
    }

    fs::create_dir_all(&demand_dir).map_err(|error| error.to_string())?;
    let demand_name = non_empty_or(&request.demand_name, "待补充");
    let lanhu_link = non_empty_or(&request.lanhu_link, "待补充");
    let notes = non_empty_or(&request.notes, "待补充");
    let mut created_files = Vec::new();

    for (_key, _label, filename) in DEMAND_INTAKE_FILES {
        let file_path = demand_dir.join(filename);
        if file_path.exists() && !file_path.is_file() {
            return Err(format!(
                "demand intake file path exists but is not a file: {}",
                file_path.display()
            ));
        }
    }

    for (key, _label, filename) in DEMAND_INTAKE_FILES {
        let file_path = demand_dir.join(filename);
        if file_path.exists() {
            continue;
        }
        fs::write(
            &file_path,
            demand_intake_template(key, &demand_name, &lanhu_link, &notes),
        )
        .map_err(|error| error.to_string())?;
        created_files.push(filename.to_string());
    }

    Ok(InitializeDemandIntakeResponse {
        status: demand_intake_status_for_workspace(&workspace),
        created_files,
    })
}

fn checked_workspace_path(workspace_path: &str) -> Result<std::path::PathBuf, String> {
    let workspace = expand_user_path(workspace_path);
    if !workspace.exists() {
        return Err(format!("workspace does not exist: {}", workspace.display()));
    }
    if !workspace.is_dir() {
        return Err(format!(
            "workspace path is not a directory: {}",
            workspace.display()
        ));
    }
    Ok(workspace)
}

fn demand_intake_status_for_workspace(workspace: &Path) -> DemandIntakeStatus {
    let demand_dir = workspace.join(DEMAND_INTAKE_DIR);
    let exists = demand_dir.is_dir();
    let files = DEMAND_INTAKE_FILES
        .iter()
        .map(|(key, label, filename)| {
            let path = demand_dir.join(filename);
            DemandIntakeFileStatus {
                key: (*key).to_string(),
                label: (*label).to_string(),
                filename: (*filename).to_string(),
                path: path.to_string_lossy().to_string(),
                exists: path.is_file(),
            }
        })
        .collect::<Vec<_>>();
    let missing_count = files.iter().filter(|file| !file.exists).count();
    DemandIntakeStatus {
        directory_path: demand_dir.to_string_lossy().to_string(),
        exists,
        ready: exists && missing_count == 0,
        missing_count,
        files,
    }
}

fn demand_intake_template(key: &str, demand_name: &str, lanhu_link: &str, notes: &str) -> String {
    match key {
        "requirement" => format!(
            "# 需求确认卡：{}\n\n## 1. 需求目标\n\n- 待整理。\n\n## 2. 页面和入口\n\n- 页面：待确认\n- 入口：待确认\n- 角色/权限：待确认\n\n## 3. 用户流程\n\n1. 待整理。\n\n## 4. UI 与交互规则\n\n- 字段：待确认\n- 按钮：待确认\n- 状态：待确认\n- 校验：待确认\n- 空状态/异常：待确认\n\n## 5. 已确认需求点\n\n- 待整理。\n\n## 6. 推断内容\n\n- 暂无。\n\n## 7. 待确认问题\n\n- P0: 待整理\n- P1: 待整理\n- P2: 待整理\n\n## 8. 建议开发范围\n\n- 本次建议实现：待确认\n- 暂不实现：待确认\n\n## 9. 验收标准\n\n- 待整理。\n\n## 输入材料\n\n- 蓝湖链接：{}\n\n### 补充说明\n\n{}\n",
            demand_name, lanhu_link, notes
        ),
        "questions" => format!(
            "# 待确认问题：{}\n\n## P0 阻塞开发\n\n- [ ] 待整理。\n\n## P1 可先做主流程但影响边界\n\n- [ ] 待整理。\n\n## P2 不阻塞开发的细节\n\n- [ ] 待整理。\n\n## 结论\n\n- P0 清零前不要进入编码。\n",
            demand_name
        ),
        "scope" => format!(
            "# 本次开发范围：{}\n\n## 已确认并实现\n\n- 待确认。\n\n## 暂不实现\n\n- 待确认。\n\n## 仍待确认\n\n- 待确认。\n\n## 进入开发条件\n\n- [ ] requirement.md 已整理。\n- [ ] questions.md 中 P0 已清零或有明确处理结论。\n- [ ] 本文件已冻结本次开发范围。\n",
            demand_name
        ),
        "tasks" => format!(
            "# 需求列表：{}\n\n> 由需求预检阶段维护。后续开发按未完成需求顺序推进，完成后回写状态。\n\n| 需求点 | 状态 | 优先级 | 来源 | 说明 |\n| --- | --- | --- | --- | --- |\n| 整理 requirement.md | 待办 | P0 | 需求预检 | 从蓝湖材料和补充说明提炼需求确认卡 |\n| 整理 questions.md | 待办 | P0 | 需求预检 | 按 P0/P1/P2 分级缺口 |\n| 冻结 scope.md | 待办 | P0 | 产品确认 | P0 清零后确认开发范围 |\n\n## 开发顺序规则\n\n- 优先处理状态为 `进行中` 或 `待办` 的 P0/P1 需求点。\n- 开发前先确认 `scope.md` 已冻结。\n- 完成需求点后，将状态更新为 `已完成`，并在 delivery.md 或 交付记录.md 补充结果。\n",
            demand_name
        ),
        "delivery" => format!(
            "# 需求交付记录：{}\n\n## 预检结论\n\n- 待整理。\n\n## 范围确认\n\n- 待整理。\n\n## 开发与验证记录\n\n- 暂无。\n\n## 遗留问题\n\n- 暂无。\n",
            demand_name
        ),
        _ => "# Document\n\n待补充。\n".to_string(),
    }
}

fn non_empty_or(value: &str, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.to_string()
    } else {
        trimmed.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_workspace(name: &str) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("nexus-core-demand-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn demand_intake_status_reports_missing_files_before_initialization() {
        let workspace = temp_workspace("missing");

        let status = read_demand_intake_status(&workspace.to_string_lossy()).unwrap();

        assert!(!status.exists);
        assert!(!status.ready);
        assert_eq!(status.missing_count, 5);
        assert!(status.directory_path.ends_with("需求"));
        assert_eq!(status.files[0].filename, "requirement.md");
    }

    #[test]
    fn initialize_demand_intake_writes_missing_files_without_overwriting_existing_content() {
        let workspace = temp_workspace("initialize");
        let demand_dir = workspace.join(DEMAND_INTAKE_DIR);
        fs::create_dir_all(&demand_dir).unwrap();
        fs::write(demand_dir.join("questions.md"), "# Existing questions\n").unwrap();

        let response = initialize_demand_intake(InitializeDemandIntakeRequest {
            workspace_path: workspace.to_string_lossy().to_string(),
            demand_name: "会员权益页".to_string(),
            lanhu_link: "https://lanhu.example/design".to_string(),
            notes: "首屏和空状态优先确认".to_string(),
            confirmed: true,
        })
        .unwrap();

        assert!(response.status.ready);
        assert_eq!(response.status.missing_count, 0);
        assert_eq!(response.created_files.len(), 4);
        assert!(!response.created_files.contains(&"questions.md".to_string()));

        let requirement = fs::read_to_string(demand_dir.join("requirement.md")).unwrap();
        assert!(requirement.contains("会员权益页"));
        assert!(requirement.contains("https://lanhu.example/design"));
        assert!(requirement.contains("首屏和空状态优先确认"));

        let existing = fs::read_to_string(demand_dir.join("questions.md")).unwrap();
        assert_eq!(existing, "# Existing questions\n");
    }

    #[test]
    fn initialize_demand_intake_requires_confirmation_and_rejects_non_file_entries() {
        let workspace = temp_workspace("rejects");

        let unconfirmed = initialize_demand_intake(InitializeDemandIntakeRequest {
            workspace_path: workspace.to_string_lossy().to_string(),
            demand_name: "Demo".to_string(),
            lanhu_link: String::new(),
            notes: String::new(),
            confirmed: false,
        });
        assert!(unconfirmed.unwrap_err().contains("requires explicit confirmation"));

        let demand_dir = workspace.join(DEMAND_INTAKE_DIR);
        fs::create_dir_all(demand_dir.join("tasks.md")).unwrap();
        let rejected = initialize_demand_intake(InitializeDemandIntakeRequest {
            workspace_path: workspace.to_string_lossy().to_string(),
            demand_name: "Demo".to_string(),
            lanhu_link: String::new(),
            notes: String::new(),
            confirmed: true,
        });
        assert!(rejected.unwrap_err().contains("exists but is not a file"));
        assert!(!demand_dir.join("requirement.md").exists());
    }
}
