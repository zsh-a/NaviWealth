use super::Strings;
impl Strings {
    pub fn missing_rate_days(&self, currency: &str, count: usize) -> String {
        if self.zh() {
            format!("有 {count} 天缺少 {currency} 汇率")
        } else {
            format!("Days missing {currency} rates: {count}")
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
