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
    pub fn quotes_failed(&self) -> &'static str {
        if self.zh() {
            "部分价格或汇率未刷新，保留原值及日期。"
        } else {
            "Some prices or FX rates could not refresh. Previous values and dates are kept."
        }
    }
}
