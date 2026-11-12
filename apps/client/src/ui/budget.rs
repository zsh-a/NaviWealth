//! One presentation contract for budget text and bounded geometry.
use super::*;
use rust_decimal::Decimal;
#[derive(Clone)]
pub struct BudgetDisplay {
    pub usage: String,
    pub balance: String,
    pub progress: f32,
    pub alert: bool,
    pub near: bool,
}
impl BudgetDisplay {
    pub fn new(spent: Decimal, limit: Decimal, currency: &str) -> Self {
        let fraction = (limit > Decimal::ZERO)
            .then(|| spent.checked_div(limit))
            .flatten();
        let usage = fraction
            .and_then(|v| v.checked_mul(100.into()))
            .map(|p| format!("{p:.1}% 已用"))
            .unwrap_or_else(|| "无预算额度".into());
        let balance = limit
            .checked_sub(spent)
            .map(|remaining| {
                format!(
                    "{} {} {currency}",
                    if remaining < Decimal::ZERO {
                        "超出"
                    } else {
                        "可用"
                    },
                    money_for(remaining.abs(), currency)
                )
            })
            .unwrap_or_else(|| "预算余额超出范围".into());
        Self {
            usage,
            balance,
            progress: if limit <= Decimal::ZERO && spent > Decimal::ZERO {
                1.0
            } else {
                ratio(spent, limit)
            },
            alert: spent >= limit && spent > Decimal::ZERO,
            near: fraction.is_some_and(|v| v >= Decimal::new(9, 1)),
        }
    }
    pub fn tone(&self) -> AdaptiveColor {
        if self.alert {
            theme().destructive
        } else if self.near {
            crate::finance_ui::warning()
        } else {
            theme().muted_foreground
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn budget_percentage_is_unbounded_while_geometry_is_bounded() {
        let b = BudgetDisplay::new(150.into(), 100.into(), "CNY");
        assert_eq!(b.usage, "150.0% 已用");
        assert_eq!(b.balance, "超出 50.00 CNY");
        assert_eq!(b.progress, 1.0);
        assert!(b.alert);
        let b = BudgetDisplay::new(90.into(), 100.into(), "JPY");
        assert!(!b.alert);
        assert!(b.near);
        assert_eq!(b.usage, "90.0% 已用");
        let b = BudgetDisplay::new(1.into(), 0.into(), "USD");
        assert!(b.alert);
        assert_eq!(b.usage, "无预算额度");
        assert_eq!(b.balance, "超出 1.00 USD");
    }
}
