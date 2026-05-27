use nexus_core::{read_document, scan_source_repos, scan_workspaces};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanWorkspacesRequest {
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanSourceReposRequest {
    source_repos_root: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReadDocumentRequest {
    path: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BridgeResponse<T: Serialize> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

#[no_mangle]
pub unsafe extern "C" fn nexus_scan_workspaces_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: ScanWorkspacesRequest| {
        scan_workspaces(
            &request.workspaces_root,
            &request.source_repos_root,
            &request.docs_root,
        )
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_scan_source_repos_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: ScanSourceReposRequest| {
        scan_source_repos(&request.source_repos_root)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_read_document_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: ReadDocumentRequest| {
        read_document(&request.path)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = CString::from_raw(value);
    }
}

unsafe fn bridge_call<Request, Response, Handler>(
    input_json: *const c_char,
    handler: Handler,
) -> *mut c_char
where
    Request: DeserializeOwned,
    Response: Serialize,
    Handler: FnOnce(Request) -> Result<Response, String>,
{
    if input_json.is_null() {
        return into_c_string(error_response::<Response>("input json pointer is null"));
    }

    let input = match CStr::from_ptr(input_json).to_str() {
        Ok(value) => value,
        Err(error) => {
            return into_c_string(error_response::<Response>(&format!(
                "input json is not valid utf-8: {error}"
            )))
        }
    };

    let request = match serde_json::from_str::<Request>(input) {
        Ok(request) => request,
        Err(error) => {
            return into_c_string(error_response::<Response>(&format!(
                "input json could not be decoded: {error}"
            )))
        }
    };

    match handler(request) {
        Ok(data) => into_c_string(BridgeResponse {
            ok: true,
            data: Some(data),
            error: None,
        }),
        Err(error) => into_c_string(error_response::<Response>(&error)),
    }
}

fn error_response<T: Serialize>(error: &str) -> BridgeResponse<T> {
    BridgeResponse {
        ok: false,
        data: None,
        error: Some(error.to_string()),
    }
}

fn into_c_string<T: Serialize>(value: T) -> *mut c_char {
    let payload = serde_json::to_string(&value)
        .unwrap_or_else(|error| format!(r#"{{"ok":false,"data":null,"error":"{error}"}}"#))
        .replace('\0', "\\u0000");
    CString::new(payload)
        .expect("nul bytes are escaped before CString creation")
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    use std::fs;

    #[test]
    fn scan_workspaces_bridge_returns_dashboard_json() {
        let root =
            std::env::temp_dir().join(format!("nexus-ffi-workspaces-{}", std::process::id()));
        let workspace = root.join("2026-05-27-bridge-demo");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Bridge Demo\n\n- 需求名称: Bridge Demo\n- 当前状态: developing\n- 目标分支: chen/bridge\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | core |\n",
        )
        .unwrap();
        fs::write(workspace.join("tasks.md"), "# Tasks\n").unwrap();
        fs::write(workspace.join("decisions.md"), "# Decisions\n").unwrap();
        fs::write(workspace.join("交付记录.md"), "# 交付记录\n\n暂无。\n").unwrap();

        let request = format!(
            r#"{{"workspacesRoot":"{}","sourceReposRoot":"~/source-repos","docsRoot":"~/docs"}}"#,
            root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_scan_workspaces_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["workspaces"][0]["name"], "Bridge Demo");
        assert_eq!(
            value["data"]["workspaces"][0]["targetBranch"],
            "chen/bridge"
        );

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn bridge_returns_json_error_for_invalid_input() {
        let input = CString::new("{not-json").unwrap();
        let output = unsafe { nexus_scan_source_repos_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], false);
        assert!(value["error"]
            .as_str()
            .unwrap()
            .contains("input json could not be decoded"));
    }

    #[test]
    fn read_document_bridge_returns_document_snapshot() {
        let root = std::env::temp_dir().join(format!("nexus-ffi-document-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let document = root.join("handoff.md");
        fs::write(&document, "# Handoff\n\nReady.\n").unwrap();

        let request = format!(r#"{{"path":"{}"}}"#, document.to_string_lossy());
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_read_document_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["name"], "handoff.md");
        assert_eq!(value["data"]["isMarkdown"], true);
        assert!(value["data"]["content"].as_str().unwrap().contains("Ready"));

        fs::remove_dir_all(root).unwrap();
    }
}
