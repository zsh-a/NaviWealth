//! Exact-decimal money. Amounts are `rust_decimal::Decimal` values paired
//! with a currency code; cross-currency arithmetic is refused unless an
//! explicit rate is applied. No floats, no minor units, no implicit
//! rounding — base-10 scale is preserved end to end.

use rust_decimal::Decimal;

/// A currency code: 3–8 uppercase ASCII letters (ISO 4217 codes fit, with
/// the same 3–8 room the ledger `unit` column allows).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Currency(String);

#[derive(Debug, thiserror::Error)]
pub enum MoneyError {
    #[error("currency code must be 3-8 ASCII letters: {0:?}")]
    InvalidCode(String),
    #[error("currency mismatch: {0} vs {1}")]
    Mismatch(String, String),
}

impl Currency {
    pub fn new(code: impl AsRef<str>) -> Result<Self, MoneyError> {
        let upper = code.as_ref().trim().to_ascii_uppercase();
        let bytes = upper.as_bytes();
        if bytes.len() < 3 || bytes.len() > 8 || !bytes.iter().all(u8::is_ascii_uppercase) {
            return Err(MoneyError::InvalidCode(code.as_ref().to_owned()));
        }
        Ok(Self(upper))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for Currency {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

/// An exact decimal amount in one currency.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Money {
    amount: Decimal,
    currency: Currency,
}

impl Money {
    pub fn new(amount: Decimal, currency: Currency) -> Self {
        Self { amount, currency }
    }

    pub fn amount(&self) -> Decimal {
        self.amount
    }

    pub fn currency(&self) -> &Currency {
        &self.currency
    }

    fn require_same(&self, rhs: &Money) -> Result<(), MoneyError> {
        if self.currency != rhs.currency {
            return Err(MoneyError::Mismatch(
                self.currency.to_string(),
                rhs.currency.to_string(),
            ));
        }
        Ok(())
    }

    pub fn checked_add(&self, rhs: &Money) -> Result<Money, MoneyError> {
        self.require_same(rhs)?;
        Ok(Money::new(self.amount + rhs.amount, self.currency.clone()))
    }

    pub fn checked_sub(&self, rhs: &Money) -> Result<Money, MoneyError> {
        self.require_same(rhs)?;
        Ok(Money::new(self.amount - rhs.amount, self.currency.clone()))
    }

    /// Convert by an explicit rate into `to`. The rate must be positive;
    /// the product keeps `rust_decimal`'s exact base-10 semantics.
    pub fn convert(&self, rate: Decimal, to: Currency) -> Result<Money, MoneyError> {
        if rate <= Decimal::ZERO {
            return Err(MoneyError::InvalidCode(format!(
                "fx rate must be positive, got {rate}"
            )));
        }
        Ok(Money::new(self.amount * rate, to))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    #[test]
    fn currency_codes_are_validated_and_normalized() {
        assert_eq!(Currency::new("usd").unwrap().as_str(), "USD");
        assert_eq!(Currency::new("CNY").unwrap().as_str(), "CNY");
        assert!(Currency::new("US").is_err());
        assert!(Currency::new("USDT012345").is_err());
        assert!(Currency::new("U S D").is_err());
    }

    #[test]
    fn cross_currency_arithmetic_is_refused() {
        let usd = Money::new(Decimal::from(10), Currency::new("USD").unwrap());
        let cny = Money::new(Decimal::from(70), Currency::new("CNY").unwrap());
        assert!(usd.checked_add(&cny).is_err());
        assert!(usd.checked_sub(&cny).is_err());
    }

    #[test]
    fn same_currency_arithmetic_and_conversion() {
        let a = Money::new(
            Decimal::from_str("12.34").unwrap(),
            Currency::new("USD").unwrap(),
        );
        let b = Money::new(
            Decimal::from_str("0.06").unwrap(),
            Currency::new("USD").unwrap(),
        );
        assert_eq!(a.checked_add(&b).unwrap().amount().to_string(), "12.40");

        let converted = a
            .convert(
                Decimal::from_str("7.25").unwrap(),
                Currency::new("CNY").unwrap(),
            )
            .unwrap();
        assert_eq!(converted.amount().to_string(), "89.4650");
        assert_eq!(converted.currency().as_str(), "CNY");

        assert!(
            a.convert(Decimal::ZERO, Currency::new("CNY").unwrap())
                .is_err()
        );
    }
}
