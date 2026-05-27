use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsProfile {
    pub schema_version: u8,
    pub app: String,
    pub exported_at: String,
    pub settings: SettingsProfileSettings,
    pub notes: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsProfileSettings {
    pub workspaces_root: String,
    pub source_repos_root: String,
    pub docs_root: String,
    pub codex_url: String,
    pub refresh_interval_seconds: usize,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportSettingsProfileResponse {
    pub path: String,
}

pub fn export_settings_profile(
    profile_dir: &Path,
    profile: &SettingsProfile,
) -> Result<ExportSettingsProfileResponse, String> {
    validate_settings_profile(profile)?;

    fs::create_dir_all(profile_dir).map_err(|error| error.to_string())?;
    let export_date = profile.exported_at.chars().take(10).collect::<String>();
    let filename = format!(
        "nexus-settings-profile-{}.json",
        sanitize_filename(&export_date)
    );
    let profile_path = profile_dir.join(filename);
    let payload = serde_json::to_string_pretty(profile).map_err(|error| error.to_string())?;
    fs::write(&profile_path, payload).map_err(|error| error.to_string())?;
    Ok(ExportSettingsProfileResponse {
        path: profile_path.to_string_lossy().to_string(),
    })
}

fn validate_settings_profile(profile: &SettingsProfile) -> Result<(), String> {
    if profile.app != "Nexus" || profile.schema_version != 1 {
        return Err("unsupported Nexus settings profile".to_string());
    }
    Ok(())
}

fn sanitize_filename(value: &str) -> String {
    let sanitized = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_') {
                character
            } else {
                '-'
            }
        })
        .collect::<String>();
    if sanitized.is_empty() {
        "export".to_string()
    } else {
        sanitized
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn export_settings_profile_writes_valid_nexus_profile() {
        let root = std::env::temp_dir().join(format!("nexus-core-settings-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let profile = SettingsProfile {
            schema_version: 1,
            app: "Nexus".to_string(),
            exported_at: "2026-05-27T03:30:00Z".to_string(),
            settings: SettingsProfileSettings {
                workspaces_root: "~/ks_project/workspaces".to_string(),
                source_repos_root: "~/ks_project/source-repos".to_string(),
                docs_root: "~/ks_project/docs".to_string(),
                codex_url: "codex://".to_string(),
                refresh_interval_seconds: 10,
            },
            notes: vec!["share local paths".to_string()],
        };

        let exported = export_settings_profile(&root, &profile).unwrap();
        let exported_path = PathBuf::from(exported.path);
        assert_eq!(
            exported_path.file_name().unwrap().to_string_lossy(),
            "nexus-settings-profile-2026-05-27.json"
        );
        let content = fs::read_to_string(&exported_path).unwrap();
        assert!(content.contains("\"app\": \"Nexus\""));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn export_settings_profile_rejects_unrelated_profiles() {
        let profile = SettingsProfile {
            schema_version: 1,
            app: "Other".to_string(),
            exported_at: "2026-05-27T03:30:00Z".to_string(),
            settings: SettingsProfileSettings {
                workspaces_root: "~/workspaces".to_string(),
                source_repos_root: "~/source".to_string(),
                docs_root: "~/docs".to_string(),
                codex_url: "codex://".to_string(),
                refresh_interval_seconds: 10,
            },
            notes: Vec::new(),
        };

        let error = export_settings_profile(Path::new("/tmp/unused"), &profile).unwrap_err();
        assert_eq!(error, "unsupported Nexus settings profile");
    }
}
