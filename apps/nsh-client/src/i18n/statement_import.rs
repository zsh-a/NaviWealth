//! Import copy kept alongside the flow rather than expanding the global dictionary.
use crate::{domain::recognition::Lang, i18n::s};
pub fn copy(en: &'static str, zh: &'static str) -> &'static str {
    if s().lang == Lang::Zh { zh } else { en }
}
pub fn title() -> &'static str {
    copy("Import statement", "导入账单")
}
pub fn pick() -> &'static str {
    copy("Choose statement file", "选择账单文件")
}
pub fn formats() -> &'static str {
    copy(
        "Alipay CSV · WeChat XLSX · CMB statement text. Files stay on this device.",
        "支付宝 CSV · 微信 XLSX · 招行账单文本。文件只在本机处理。",
    )
}
pub fn stale() -> &'static str {
    copy(
        "Your journal changed. Review the updated duplicates and confirm again.",
        "账本已变更，请核对更新后的重复记录，再次确认。",
    )
}
pub fn failed() -> &'static str {
    copy(
        "Could not save. Your review is retained; try again.",
        "未能保存，核对内容已保留，请重试。",
    )
}
pub fn unreadable() -> &'static str {
    copy(
        "Cannot read this statement. Choose a CSV, XLSX or CMB text export. PDF is not supported.",
        "无法读取账单，请选择 CSV、XLSX 或招行文本导出。暂不支持 PDF。",
    )
}
pub fn method() -> &'static str {
    copy(
        "Choose the account for this payment method",
        "为付款方式选择账户",
    )
}
pub fn remember() -> &'static str {
    copy(
        "Mappings are remembered only when you confirm the import.",
        "确认导入后才会记住账户映射。",
    )
}
pub fn other() -> &'static str {
    copy("Choose the other own account", "选择另一自有账户")
}
pub fn refund() -> &'static str {
    copy("Refund", "退款")
}
pub fn incoming() -> &'static str {
    copy("Transfer into this account", "转入此账户")
}
pub fn outgoing() -> &'static str {
    copy("Transfer out of this account", "从此账户转出")
}
pub fn attention() -> &'static str {
    copy("Needs correction", "待补充")
}
pub fn duplicate() -> &'static str {
    copy("Already imported", "已导入")
}
pub fn possible() -> &'static str {
    copy(
        "Possible duplicate · review before import",
        "疑似重复 · 默认不选",
    )
}
pub fn ready() -> &'static str {
    copy("New", "新增")
}
pub fn skip() -> &'static str {
    copy("Skipped source lines", "跳过的原始行")
}
pub fn issues() -> &'static str {
    copy(
        "Failed, cancelled, refunded purchase statuses and invalid rows stay out of the journal. Export a corrected file for invalid dates or amounts.",
        "失败、取消、已退款的原购买记录和无效行不会写入账本。日期或金额有误时请修正文件后重新导入。",
    )
}
