//! Listing lookup copy kept together in both interface languages.
use super::s;
pub fn copy(en: &'static str, zh: &'static str) -> &'static str {
    if s().zh() { zh } else { en }
}
pub fn title() -> &'static str {
    copy("Find a security", "查找证券")
}
pub fn search() -> &'static str {
    copy("Code, name or pinyin", "代码、名称或拼音")
}
pub fn empty() -> &'static str {
    copy(
        "No matching listings. Try another code or enter a holding manually.",
        "未找到匹配证券。可更换代码搜索，或手动填写持仓。",
    )
}
pub fn hint() -> &'static str {
    copy(
        "Search offline mainland, Hong Kong and US stocks and ETFs (CNY, HKD, USD).",
        "离线搜索内地、香港和美国股票及 ETF（人民币、港币、美元）。",
    )
}
pub fn unsupported() -> &'static str {
    copy(
        "Currency or instrument not supported",
        "暂不支持此币种或证券类型",
    )
}
pub fn choose() -> &'static str {
    copy("Search securities", "搜索证券")
}
pub fn manual() -> &'static str {
    copy("Enter manually", "手动填写")
}
pub fn bind() -> &'static str {
    copy("Link a listed security", "关联证券代码")
}
pub fn confirm() -> &'static str {
    copy("Confirm link", "确认关联")
}
pub fn body() -> &'static str {
    copy(
        "Check the market and code. This links quotes only; the holding name, trades and cost stay as recorded.",
        "请核对市场与代码。关联仅用于行情；持仓名称、交易和成本记录保留原样。",
    )
}
pub fn market_price() -> &'static str {
    copy("Tencent price", "腾讯行情")
}
pub fn previous_close() -> &'static str {
    copy("Previous close", "前收盘价")
}
pub fn stale() -> &'static str {
    copy("Earlier quote", "历史行情")
}

pub fn bind_failed() -> &'static str {
    copy(
        "Could not link this security. Try again.",
        "未能关联证券，请重试。",
    )
}

pub fn market(key: &str) -> &'static str {
    match key {
        "cn_a" => copy("Mainland China", "中国内地"),
        "hk_stock" => copy("Hong Kong", "香港"),
        "us_stock" => copy("United States", "美国"),
        "crypto" => copy("Crypto", "加密资产"),
        "fx" => copy("Foreign exchange", "外汇"),
        _ => copy("Other market", "其他市场"),
    }
}
