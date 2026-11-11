//! User-selected encrypted backup file exchange; Android uses SAF content URIs.
use crate::state::Services;
use std::{path::PathBuf, sync::Arc};

pub async fn export_backup(services: &Arc<Services>, source: PathBuf) -> Result<bool, String> {
    let name = source
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("NaviWealth.bak")
        .to_owned();
    #[cfg(target_os = "android")]
    {
        let _ = services;
        lifeos_platform::documents::export_file(source, name)
            .await
            .map(|path| path.is_some())
    }
    #[cfg(not(target_os = "android"))]
    {
        use nsh_core::{
            element::pick_save_path,
            file_dialog::{FileFilter, SaveDialog},
        };
        let destination = pick_save_path(
            SaveDialog::new()
                .title("导出加密备份")
                .file_name(name)
                .filter(FileFilter::new("NaviWealth 备份", ["bak"])),
        )
        .await
        .map_err(|_| "当前设备无法打开系统文件选择；可先保留本机副本。".to_owned())?;
        let Some(destination) = destination else {
            return Ok(false);
        };
        if destination == source {
            return Ok(true);
        }
        services
            .runtime
            .spawn_blocking(move || {
                std::fs::copy(source, destination)
                    .map(|_| true)
                    .map_err(|_| "无法保存备份，请检查目标目录".to_owned())
            })
            .await
            .map_err(|e| e.to_string())?
    }
}

pub async fn import_backup() -> Result<Option<PathBuf>, String> {
    #[cfg(target_os = "android")]
    {
        lifeos_platform::documents::import_file().await
    }
    #[cfg(not(target_os = "android"))]
    {
        use nsh_core::{
            element::pick_paths,
            file_dialog::{FileFilter, OpenDialog},
        };
        pick_paths(
            OpenDialog::files()
                .title("选择加密备份")
                .filter(FileFilter::new("NaviWealth 备份", ["bak"])),
        )
        .await
        .map_err(|_| "当前设备无法打开系统文件选择；可从此设备的备份副本恢复。".to_owned())
        .map(|paths| paths.and_then(|mut paths| (!paths.is_empty()).then(|| paths.remove(0))))
    }
}

pub fn cleanup_import(path: &std::path::Path) {
    // Android returns a private staging copy; desktop returns the user's file.
    #[cfg(target_os = "android")]
    {
        let _ = std::fs::remove_file(path);
    }
    #[cfg(not(target_os = "android"))]
    let _ = path;
}
