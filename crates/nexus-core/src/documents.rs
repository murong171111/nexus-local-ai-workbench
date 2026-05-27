use crate::expand_user_path;
use serde::Serialize;
use std::fs;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DocumentSnapshot {
    pub path: String,
    pub name: String,
    pub extension: String,
    pub is_markdown: bool,
    pub content: String,
}

pub fn read_document(path: &str) -> Result<DocumentSnapshot, String> {
    let resolved = expand_user_path(path);
    if !resolved.exists() {
        return Err(format!("document does not exist: {}", resolved.display()));
    }
    if !resolved.is_file() {
        return Err(format!(
            "document path is not a file: {}",
            resolved.display()
        ));
    }

    let content = fs::read_to_string(&resolved).map_err(|error| error.to_string())?;
    let extension = resolved
        .extension()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_default();
    let name = resolved
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| resolved.to_string_lossy().to_string());

    Ok(DocumentSnapshot {
        path: resolved.to_string_lossy().to_string(),
        name,
        is_markdown: is_markdown_extension(&extension),
        extension,
        content,
    })
}

fn is_markdown_extension(extension: &str) -> bool {
    matches!(
        extension.to_ascii_lowercase().as_str(),
        "md" | "markdown" | "mdown" | "mkdn"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_document_returns_markdown_snapshot() {
        let root = std::env::temp_dir().join(format!("nexus-core-document-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let document = root.join("交付记录.md");
        fs::write(&document, "# 交付记录\n\n暂无。\n").unwrap();

        let snapshot = read_document(&document.to_string_lossy()).unwrap();
        assert_eq!(snapshot.name, "交付记录.md");
        assert_eq!(snapshot.extension, "md");
        assert!(snapshot.is_markdown);
        assert!(snapshot.content.contains("交付记录"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn read_document_rejects_missing_files() {
        let missing = std::env::temp_dir().join(format!(
            "nexus-core-missing-document-{}.md",
            std::process::id()
        ));
        let error = read_document(&missing.to_string_lossy()).unwrap_err();
        assert!(error.contains("document does not exist"));
    }
}
