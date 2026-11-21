//! Backup file copy (export through the share sheet, restore from a file)
//! kept together for both supported languages.
use super::Strings;

impl Strings {
    pub fn backup_group_file(&self) -> &'static str {
        if self.zh() {
            "备份文件"
        } else {
            "Backup file"
        }
    }
    pub fn backup_export(&self) -> &'static str {
        if self.zh() {
            "导出备份文件"
        } else {
            "Export backup file"
        }
    }
    pub fn backup_restore_file(&self) -> &'static str {
        if self.zh() {
            "从文件恢复…"
        } else {
            "Restore from file…"
        }
    }
    pub fn backup_include_photos(&self) -> &'static str {
        if self.zh() {
            "包含餐食照片"
        } else {
            "Include meal photos"
        }
    }
    pub fn backup_exported(&self) -> &'static str {
        if self.zh() {
            "备份文件已导出"
        } else {
            "Backup file exported"
        }
    }
    pub fn backup_export_never(&self) -> &'static str {
        if self.zh() {
            "还没有导出过备份文件"
        } else {
            "No backup file exported yet"
        }
    }
    /// When a backup file last left the app.
    pub fn backup_last_export(&self, when: &str) -> String {
        if self.zh() {
            format!("上次导出：{when}")
        } else {
            format!("Last exported: {when}")
        }
    }
    pub fn backup_file_note(&self) -> &'static str {
        if self.zh() {
            "文件用上方的备份密码加密，可存到「文件」、网盘或发给自己。恢复时选择该文件，并使用同一密码。"
        } else {
            "The file is encrypted with the backup passphrase above. Keep it in Files, a drive or a chat with yourself; to restore, pick it and use the same passphrase."
        }
    }
    pub fn backup_no_passphrase(&self) -> &'static str {
        if self.zh() {
            "请先在上方填写至少 8 位的备份密码。"
        } else {
            "Enter a backup passphrase of at least 8 characters above."
        }
    }
    pub fn backup_unavailable(&self) -> &'static str {
        if self.zh() {
            "这台设备无法分享或保存文件。"
        } else {
            "This device can't share or save the file."
        }
    }
}
