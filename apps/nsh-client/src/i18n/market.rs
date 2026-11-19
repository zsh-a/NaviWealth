use super::Strings;
impl Strings {
    pub fn refresh_quotes(&self) -> &'static str {
        if self.zh() {
            "刷新价格与汇率"
        } else {
            "Refresh prices and FX"
        }
    }
    pub fn refreshing_quotes(&self) -> &'static str {
        if self.zh() {
            "正在刷新价格与汇率…"
        } else {
            "Refreshing prices and FX…"
        }
    }
    pub fn missing_rate_days(&self, currency: &str, count: usize) -> String {
        if self.zh() {
            format!("有 {count} 天缺少 {currency} 汇率")
        } else {
            format!("Days missing {currency} rates: {count}")
        }
    }
    pub fn cost_holdings(&self, count: usize) -> String {
        if self.zh() {
            format!("{count} 项持仓按成本计入")
        } else {
            format!("Holdings valued at cost: {count}")
        }
    }
    pub fn refresh_summary(&self, time: &str, updated: usize, failed: usize) -> String {
        if self.zh() {
            format!("{time} 刷新 · 更新 {updated} 项 · 失败 {failed} 项")
        } else {
            format!("Checked {time} · {updated} updated · {failed} failed")
        }
    }
}
