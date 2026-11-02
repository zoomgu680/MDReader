// MDReader - Tauri 后端入口
// 提供：读取文件、最近文件管理、文件关联启动

#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

// 最近文件列表的持久化路径
fn recent_file_path() -> PathBuf {
    let dir = dirs::config_dir()
        .or_else(|| dirs::data_dir())
        .unwrap_or_else(|| PathBuf::from("."))
        .join("mdreader");
    fs::create_dir_all(&dir).ok();
    dir.join("recent.json")
}

// 读取 MD 文件内容
#[tauri::command]
fn read_file(path: String) -> Result<String, String> {
    fs::read_to_string(&path).map_err(|e| format!("读取文件失败: {}", e))
}

// 写入 MD 文件内容（编辑保存）
#[tauri::command]
fn write_file(path: String, contents: String) -> Result<(), String> {
    fs::write(&path, contents).map_err(|e| format!("写入文件失败: {}", e))
}

// 读取二进制文件（图片），返回 base64 编码
#[tauri::command]
fn read_binary_file(path: String) -> Result<String, String> {
    let bytes = fs::read(&path).map_err(|e| format!("读取文件失败: {}", e))?;
    use base64::{engine::general_purpose, Engine};
    Ok(general_purpose::STANDARD.encode(&bytes))
}

// 写入二进制文件（Word 导出），入参为 base64 编码
#[tauri::command]
fn write_binary_file(path: String, data_base64: String) -> Result<(), String> {
    use base64::{engine::general_purpose, Engine};
    let bytes = general_purpose::STANDARD
        .decode(&data_base64)
        .map_err(|e| format!("解码失败: {}", e))?;
    fs::write(&path, bytes).map_err(|e| format!("写入文件失败: {}", e))
}

// 文件综合信息：大小、创建/修改时间、所有者（创建人）
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct FileInfo {
    size: u64,
    created_ms: Option<u64>,
    modified_ms: Option<u64>,
    owner: Option<String>,
}

fn system_time_ms(t: std::time::SystemTime) -> Option<u64> {
    t.duration_since(std::time::UNIX_EPOCH)
        .ok()
        .map(|d| d.as_millis() as u64)
}

#[tauri::command]
fn get_file_info(path: String) -> Result<FileInfo, String> {
    let meta = fs::metadata(&path).map_err(|e| format!("读取文件信息失败: {}", e))?;
    Ok(FileInfo {
        size: meta.len(),
        created_ms: meta.created().ok().and_then(system_time_ms),
        modified_ms: meta.modified().ok().and_then(system_time_ms),
        owner: file_owner(&path),
    })
}

// 文件所有者（Windows 通过 ACL 查询，Unix 通过 stat 查询）
#[cfg(target_os = "windows")]
fn file_owner(path: &str) -> Option<String> {
    let escaped = path.replace('\'', "''");
    let script = format!(
        "$ErrorActionPreference='SilentlyContinue'; \
         [Console]::OutputEncoding=[System.Text.Encoding]::UTF8; \
         $acl = Get-Acl -LiteralPath '{}'; if ($acl) {{ $acl.Owner }}",
        escaped
    );
    let output = std::process::Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", script.as_str()])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() { None } else { Some(text) }
}

#[cfg(target_os = "macos")]
fn file_owner(path: &str) -> Option<String> {
    let output = std::process::Command::new("stat").args(["-f", "%Su", path]).output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() { None } else { Some(text) }
}

#[cfg(all(unix, not(target_os = "macos")))]
fn file_owner(path: &str) -> Option<String> {
    let output = std::process::Command::new("stat").args(["-c", "%U", path]).output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() { None } else { Some(text) }
}

#[cfg(not(any(windows, unix)))]
fn file_owner(_path: &str) -> Option<String> {
    None
}

// 获取最近打开的文件列表
#[tauri::command]
fn get_recent_files() -> Vec<String> {
    let p = recent_file_path();
    fs::read_to_string(&p)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

// 加入最近文件列表（去重、最多保留 10 条）
#[tauri::command]
fn add_recent_file(path: String) -> Vec<String> {
    let p = recent_file_path();
    let mut list: Vec<String> = fs::read_to_string(&p)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    list.retain(|x| x != &path);
    list.insert(0, path);
    list.truncate(10);
    fs::write(&p, serde_json::to_string(&list).unwrap_or_default()).ok();
    list
}

// 获取上次打开的文件
#[tauri::command]
fn get_last_file() -> Option<String> {
    get_recent_files().into_iter().next()
}

// 启动文件状态：保存命令行传入的 .md 路径
struct StartupFile(Mutex<Option<String>>);

#[tauri::command]
fn get_startup_file(state: tauri::State<StartupFile>) -> Option<String> {
    let guard = state.0.lock().unwrap();
    guard.clone()
}

fn main() {
    // 解析命令行参数，找第一个 .md 文件
    let startup_file: Option<String> = std::env::args()
        .skip(1)
        .find(|a| a.to_lowercase().ends_with(".md") || a.to_lowercase().ends_with(".markdown"));

    let startup_state = StartupFile(Mutex::new(startup_file));

    use tauri::Manager;

    tauri::Builder::default()
        .manage(startup_state)
        .invoke_handler(tauri::generate_handler![
            read_file,
            write_file,
            read_binary_file,
            write_binary_file,
            get_file_info,
            get_recent_files,
            add_recent_file,
            get_last_file,
            get_startup_file,
        ])
        .setup(|app| {
            // 动态调整窗口大小为当前屏幕分辨率的 90%，并居中
            if let Some(window) = app.get_window("main") {
                if let Ok(monitor) = window.current_monitor() {
                    if let Some(monitor) = monitor {
                        let size = monitor.size();
                        let scale = monitor.scale_factor();
                        // 物理像素 → 逻辑像素
                        let logical_w = (size.width as f64 / scale) * 0.9;
                        let logical_h = (size.height as f64 / scale) * 0.9;
                        let w = logical_w.round() as i32;
                        let h = logical_h.round() as i32;
                        let _ = window.set_size(tauri::LogicalSize::new(w, h));
                        let _ = window.center();
                    }
                }
            }
            Ok(())
        })
        .on_window_event(|event| {
            // 拖放处理
            if let tauri::WindowEvent::FileDrop(file_drop) = event.event() {
                use tauri::FileDropEvent;
                match file_drop {
                    FileDropEvent::Dropped(paths) => {
                        if let Some(first) = paths.first() {
                            let path = first.to_string_lossy().to_string();
                            let js = format!(
                                "if (window.__TAURI_BRIDGE__) {{ window.__TAURI_BRIDGE__.loadByPath({:?}) }}",
                                path
                            );
                            let _ = event.window().eval(&js);
                        }
                    }
                    _ => {}
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running MDReader");
}
