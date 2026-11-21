//! Copy for content shared from other apps, in both supported languages.
use super::Strings;

impl Strings {
    pub fn incoming_unsupported(&self) -> &'static str {
        if self.zh() {
            "无法打开分享的内容：支持图片、文字和账单文件（CSV、XLSX、TXT）。"
        } else {
            "Can't open what was shared: images, text and statement files (CSV, XLSX, TXT) are supported."
        }
    }
    pub fn incoming_statement_busy(&self) -> &'static str {
        if self.zh() {
            "请先完成或放弃正在核对的账单，再导入新的。"
        } else {
            "Finish or discard the statement in review before importing another."
        }
    }
}
