//! Review copy kept together for both supported languages.
use super::Strings;
use navi_finance::money;
impl Strings {
    pub fn recorded_spending(&self) -> &'static str {
        if self.zh() {
            "已记录支出"
        } else {
            "Recorded spending"
        }
    }
    pub fn spending_empty(&self) -> &'static str {
        if self.zh() {
            "这段时间没有支出记录"
        } else {
            "No spending recorded for this period"
        }
    }
    pub fn spending_basis(&self) -> &'static str {
        if self.zh() {
            "退款已抵扣；仅包含已记录的支出。"
        } else {
            "Recorded expenses only, with refunds deducted."
        }
    }
    pub fn spending_more(&self) -> &'static str {
        if self.zh() {
            "更多分类"
        } else {
            "More categories"
        }
    }
    pub fn spending_comparison(&self, current: i64, previous: Option<i64>) -> String {
        let Some(previous) = previous else {
            return if self.zh() {
                "上一对比时段没有支出记录"
            } else {
                "No spending recorded in the comparison period"
            }
            .into();
        };
        let delta = i128::from(current) - i128::from(previous);
        let amount = money::format(money::saturate(delta.abs()));
        match (self.zh(), delta.cmp(&0)) {
            (true, std::cmp::Ordering::Greater) => format!("比上一对比时段多 ¥{amount}"),
            (true, std::cmp::Ordering::Less) => format!("比上一对比时段少 ¥{amount}"),
            (true, _) => "与上一对比时段持平".into(),
            (false, std::cmp::Ordering::Greater) => {
                format!("¥{amount} more than the comparison period")
            }
            (false, std::cmp::Ordering::Less) => {
                format!("¥{amount} less than the comparison period")
            }
            (false, _) => "Unchanged from the comparison period".into(),
        }
    }
}
