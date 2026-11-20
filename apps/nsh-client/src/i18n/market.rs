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
    pub fn excluded_currencies(&self, codes: &str) -> String {
        if self.zh() {
            format!("{codes} 未计入 · 补充汇率")
        } else {
            format!("{codes} excluded · Add exchange rate")
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
    pub fn refresh_summary(&self, time: &str, updated: usize, failed: usize) -> String {
        if self.zh() {
            if failed == 0 {
                format!("{time} · 已更新 {updated} 项")
            } else {
                format!("{time} · 已更新 {updated} 项，{failed} 项更新失败")
            }
        } else {
            if failed == 0 {
                format!("{time} · {updated} updated")
            } else {
                format!("{time} · {updated} updated · {failed} failed")
            }
        }
    }
}
