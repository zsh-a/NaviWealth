//! Review's net-worth change copy kept together for both supported languages.
use navi_finance::{attribution::Part, currency::Currency};

use super::Strings;
use crate::domain::meal::Day;

impl Strings {
    pub fn net_worth_change(&self) -> &'static str {
        if self.zh() {
            "净资产变化"
        } else {
            "Net worth change"
        }
    }
    pub fn net_worth_part(&self, part: Part) -> &'static str {
        match (self.zh(), part) {
            (true, Part::Income) => "收入",
            (true, Part::Spending) => "支出",
            (true, Part::Investment) => "投资",
            (true, Part::Openings) => "期初余额",
            (true, Part::Adjustments) => "余额校准",
            (true, Part::Exchange) => "汇率",
            (false, Part::Income) => "Income",
            (false, Part::Spending) => "Spending",
            (false, Part::Investment) => "Investments",
            (false, Part::Openings) => "Opening balances",
            (false, Part::Adjustments) => "Balance corrections",
            (false, Part::Exchange) => "Exchange rates",
        }
    }
    /// The close the change starts from and both values: `Oct 31 close ¥1.00 → ¥2.00`.
    pub fn net_worth_span(&self, start_day: Day, start: &str, end: &str) -> String {
        if self.zh() {
            format!("{}收盘 {start} → {end}", self.short_date(start_day))
        } else {
            format!("{} close {start} → {end}", self.short_date(start_day))
        }
    }
    pub fn net_worth_unchanged(&self) -> &'static str {
        if self.zh() {
            "这段时间净资产没有变化。"
        } else {
            "Net worth did not change in this period."
        }
    }
    pub fn net_worth_missing(&self, missing: &[Currency]) -> String {
        let codes: Vec<_> = missing.iter().map(|c| c.code()).collect();
        if self.zh() {
            format!("缺少 {} 汇率", codes.join("、"))
        } else {
            format!("Missing exchange rates · {}", codes.join(", "))
        }
    }
    pub fn net_worth_basis(&self) -> &'static str {
        if self.zh() {
            "收支按期初汇率折算。"
        } else {
            "Income and spending use the opening exchange rates."
        }
    }
    pub fn net_worth_other_investments(&self) -> &'static str {
        if self.zh() {
            "其他投资"
        } else {
            "Other investments"
        }
    }
    pub fn net_worth_details(&self, open: bool) -> &'static str {
        match (self.zh(), open) {
            (true, false) => "展开明细",
            (true, true) => "收起明细",
            (false, false) => "Show details",
            (false, true) => "Hide details",
        }
    }
    /// The Review headline when only the ledger changed.
    pub fn net_worth_summary(&self, change: &str, rose: bool) -> String {
        match (self.zh(), rose) {
            (true, true) => format!("本期净资产增加 {change}。"),
            (true, false) => format!("本期净资产减少 {change}。"),
            (false, true) => format!("Net worth rose {change} this period."),
            (false, false) => format!("Net worth fell {change} this period."),
        }
    }
}
