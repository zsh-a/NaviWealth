use super::Strings;

pub(crate) fn source_label(source: &str) -> &str {
    use super::catalog::copy;
    match source {
        "manual" => super::s().manual_source,
        "base" => copy("Base currency", "本位币"),
        "cost" => copy("Cost", "成本"),
        "tencent" => super::catalog::market_price(),
        "tencent:raw" => copy("Tencent unadjusted close", "腾讯未复权收盘价"),
        "frankfurter:ecb" => copy("ECB", "欧洲央行"),
        "dated" | "" => copy("Unknown source", "来源未知"),
        other => other,
    }
}

impl Strings {
    pub fn missing_rate(&self, currency: &str) -> String {
        if self.zh() {
            format!("缺少 {currency} 汇率")
        } else {
            format!("Missing {currency} rate")
        }
    }
    pub fn excluded_currencies(&self, codes: &str) -> String {
        if self.zh() {
            format!("{codes} 未计入 · 缺少汇率")
        } else {
            format!("{codes} excluded · Missing rate")
        }
    }
    pub fn cost_count(&self, count: usize) -> String {
        if self.zh() {
            format!("{count} 项按成本计")
        } else {
            format!("{count} at cost")
        }
    }
    pub fn cost_holdings(&self, count: usize) -> String {
        if self.zh() {
            format!("{count} 项持仓按成本计入")
        } else {
            format!("Holdings valued at cost: {count}")
        }
    }
}
