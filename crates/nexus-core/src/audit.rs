use crate::expand_user_path;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub const AUDIT_LOG_FILE: &str = "audit-log.jsonl";

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditEventInput {
    pub actor: String,
    pub action: String,
    pub target: String,
    pub summary: String,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditEvent {
    pub id: String,
    pub timestamp: String,
    pub actor: String,
    pub action: String,
    pub target: String,
    pub summary: String,
    pub metadata: BTreeMap<String, String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppendAuditEventResponse {
    pub path: String,
    pub event: AuditEvent,
}

pub fn append_audit_event(
    audit_root: impl AsRef<Path>,
    input: AuditEventInput,
) -> Result<AppendAuditEventResponse, String> {
    let audit_root = audit_root.as_ref();
    fs::create_dir_all(audit_root).map_err(|error| error.to_string())?;

    let event = AuditEvent {
        id: audit_event_id(&input.action, &input.target),
        timestamp: audit_timestamp(),
        actor: non_empty_or(input.actor, "Nexus"),
        action: non_empty_or(input.action, "unknown"),
        target: non_empty_or(input.target, "unknown"),
        summary: non_empty_or(input.summary, "No summary provided"),
        metadata: input.metadata,
    };
    let path = audit_log_path(audit_root);
    let payload = serde_json::to_string(&event).map_err(|error| error.to_string())?;
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|error| error.to_string())?;
    writeln!(file, "{payload}").map_err(|error| error.to_string())?;

    Ok(AppendAuditEventResponse {
        path: path.to_string_lossy().to_string(),
        event,
    })
}

pub fn append_audit_event_from_root(
    audit_root: &str,
    input: AuditEventInput,
) -> Result<AppendAuditEventResponse, String> {
    append_audit_event(expand_user_path(audit_root), input)
}

pub fn audit_log_path(audit_root: impl AsRef<Path>) -> PathBuf {
    audit_root.as_ref().join(AUDIT_LOG_FILE)
}

fn audit_event_id(action: &str, target: &str) -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or_default();
    format!(
        "audit-{}-{}-{millis}",
        sanitize_id_segment(action),
        sanitize_id_segment(target)
    )
}

fn audit_timestamp() -> String {
    Command::new("date")
        .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
        .output()
        .ok()
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            let millis = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_millis())
                .unwrap_or_default();
            format!("unix-ms:{millis}")
        })
}

fn non_empty_or(value: String, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.to_string()
    } else {
        trimmed.to_string()
    }
}

fn sanitize_id_segment(value: &str) -> String {
    let sanitized = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_') {
                character
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string();
    if sanitized.is_empty() {
        "event".to_string()
    } else {
        sanitized
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn append_audit_event_writes_jsonl_events() {
        let root = std::env::temp_dir().join(format!("nexus-core-audit-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);

        let mut metadata = BTreeMap::new();
        metadata.insert("workspace".to_string(), "2026-05-27-demo".to_string());
        let first = append_audit_event(
            &root,
            AuditEventInput {
                actor: "Nexus Test".to_string(),
                action: "workspace.created".to_string(),
                target: "/tmp/demo".to_string(),
                summary: "Created workspace".to_string(),
                metadata,
            },
        )
        .unwrap();
        let second = append_audit_event(
            &root,
            AuditEventInput {
                actor: "".to_string(),
                action: "settings.exported".to_string(),
                target: "/tmp/profile.json".to_string(),
                summary: "Exported profile".to_string(),
                metadata: BTreeMap::new(),
            },
        )
        .unwrap();

        assert_eq!(first.path, second.path);
        let lines = fs::read_to_string(audit_log_path(&root)).unwrap();
        let events = lines
            .lines()
            .map(|line| serde_json::from_str::<Value>(line).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(events.len(), 2);
        assert_eq!(events[0]["action"], "workspace.created");
        assert_eq!(events[0]["metadata"]["workspace"], "2026-05-27-demo");
        assert_eq!(events[1]["actor"], "Nexus");
        assert!(events[0]["id"].as_str().unwrap().starts_with("audit-"));
        assert!(!events[0]["timestamp"].as_str().unwrap().is_empty());

        fs::remove_dir_all(root).unwrap();
    }
}
