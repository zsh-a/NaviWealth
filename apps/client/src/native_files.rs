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

/// Reliable statement import contract: bounded UTF-8 CSV bytes, selected by the
/// user through the platform picker. Cancellation creates no staging file or batch.
pub async fn import_statement_csv() -> Result<Option<String>, String> {
    #[cfg(target_os = "android")]
    let selection = lifeos_platform::documents::import_statement_csv().await?;
    #[cfg(not(target_os = "android"))]
    let selection = {
        use nsh_core::{
            element::pick_paths,
            file_dialog::{FileFilter, OpenDialog},
        };
        pick_paths(
            OpenDialog::files()
                .title("选择 UTF-8 CSV 账单")
                .filter(FileFilter::new("CSV 账单", ["csv", "txt"])),
        )
        .await
        .map_err(|_| "当前设备无法打开文件选择；可使用粘贴 CSV 导入。".to_owned())?
        .and_then(|paths| paths.into_iter().next())
    };
    let Some(path) = selection else {
        return Ok(None);
    };
    let file = StatementFile {
        path,
        cleanup: cfg!(target_os = "android"),
    };
    let services = Services::shared();
    services
        .runtime
        .spawn_blocking(move || read_statement_file(file))
        .await
        .map_err(|_| "CSV 读取中断，请重新选择文件".to_owned())?
        .map(Some)
}
const MAX_STATEMENT_BYTES: u64 = 10_000_000;
struct StatementFile {
    path: PathBuf,
    cleanup: bool,
}
impl Drop for StatementFile {
    fn drop(&mut self) {
        if self.cleanup {
            let _ = std::fs::remove_file(&self.path);
        }
    }
}
fn read_statement_file(file: StatementFile) -> Result<String, String> {
    use std::io::Read;
    let input = std::fs::File::open(&file.path)
        .map_err(|_| "无法读取 CSV，请检查文件权限并重试".to_owned())?;
    if input
        .metadata()
        .map_err(|_| "无法读取 CSV 文件信息".to_owned())?
        .len()
        > MAX_STATEMENT_BYTES
    {
        return Err("CSV 超过 10 MB，请拆分后导入".into());
    }
    let mut bytes = Vec::new();
    input
        .take(MAX_STATEMENT_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "CSV 读取失败，请重新选择文件".to_owned())?;
    if bytes.len() as u64 > MAX_STATEMENT_BYTES {
        return Err("CSV 超过 10 MB，请拆分后导入".into());
    }
    let text = String::from_utf8(bytes)
        .map_err(|_| "CSV 须为 UTF-8 编码，可包含 BOM；请重新导出文件".to_owned())?;
    if text.contains('\0') {
        return Err("请选择文本 CSV 文件，当前内容包含无效文本字节".into());
    }
    Ok(text)
}
#[cfg(test)]
mod statement_tests {
    use super::*;
    fn temporary() -> PathBuf {
        std::env::temp_dir().join(format!(
            "naviwealth-statement-test-{}.csv",
            uuid::Uuid::new_v4()
        ))
    }
    #[test]
    fn utf8_statement_read_removes_only_private_staging() {
        let path = temporary();
        std::fs::write(&path, b"date,amount,currency,direction,counterparty,note\n").unwrap();
        assert!(
            read_statement_file(StatementFile {
                path: path.clone(),
                cleanup: true
            })
            .unwrap()
            .starts_with("date,")
        );
        assert!(!path.exists());
        std::fs::write(&path, "UTF-8 账单").unwrap();
        assert_eq!(
            read_statement_file(StatementFile {
                path: path.clone(),
                cleanup: false
            })
            .unwrap(),
            "UTF-8 账单"
        );
        assert!(path.exists());
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn oversized_and_non_utf8_staging_is_cleaned_on_every_error() {
        let path = temporary();
        let file = std::fs::File::create(&path).unwrap();
        file.set_len(MAX_STATEMENT_BYTES + 1).unwrap();
        drop(file);
        assert!(
            read_statement_file(StatementFile {
                path: path.clone(),
                cleanup: true
            })
            .unwrap_err()
            .contains("10 MB")
        );
        assert!(!path.exists());
        for bytes in [vec![0xff, 0xfe], vec![b'a', 0, b'b']] {
            std::fs::write(&path, bytes).unwrap();
            assert!(
                read_statement_file(StatementFile {
                    path: path.clone(),
                    cleanup: true
                })
                .is_err()
            );
            assert!(!path.exists());
        }
    }
    #[test]
    fn abandoned_staging_owner_cleans_up_without_reading() {
        let path = temporary();
        std::fs::write(&path, "staged").unwrap();
        drop(StatementFile {
            path: path.clone(),
            cleanup: true,
        });
        assert!(!path.exists());
    }
}
