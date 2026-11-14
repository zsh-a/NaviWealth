//! The text layer of a CMB (招商银行) credit-card statement: one line per
//! card transaction, `交易日 [记账日] 摘要 人民币金额 卡号末四位 结算金额`.
//! The settled amount is the CNY that hit the card. Ported from the
//! Flutter client's `cmb_credit_card_ingest_parser.dart`: positive rows are
//! card spending; negative rows (repayments, refunds) are issues for now.

use std::sync::LazyLock;

use jiff::civil::Date;
use regex::Regex;

use super::{Issue, IssueCode, Kind, Row};
use crate::money;

static PERIOD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(20\d{2})年(\d{2})月").unwrap());
static CANDIDATE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^\s*\d{2}/\d{2}\s+").unwrap());
static TRANSACTION: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^\s*(\d{2})/(\d{2})\s+(?:(\d{2})/(\d{2})\s+)?(.+?)\s+(-?[\d,]+\.\d{2})\s+(\d{4})\s+(-?[\d,]+\.\d{2})(?:\(([A-Z]{2})\))?\s*$",
    )
    .unwrap()
});

/// Whether `raw` is a CMB credit-card statement.
pub fn is_statement(raw: &str) -> bool {
    raw.contains("招商银行信用卡对账单") && raw.contains("交易明细") && PERIOD.is_match(raw)
}

pub(super) fn parse(raw: &str, default_currency: &str) -> (Vec<Row>, Vec<Issue>, usize) {
    let Some(period) = PERIOD.captures(raw) else {
        return (Vec::new(), Vec::new(), 0);
    };
    let (Ok(year), Ok(month)) = (period[1].parse::<i16>(), period[2].parse::<i8>()) else {
        return (Vec::new(), Vec::new(), 0);
    };
    let mut rows = Vec::new();
    let mut issues = Vec::new();
    let mut candidates = 0;
    for (index, line) in raw.lines().enumerate() {
        if !CANDIDATE.is_match(line) {
            continue;
        }
        candidates += 1;
        let issue = |code| Issue {
            line: index + 1,
            code,
        };
        let Some(m) = TRANSACTION.captures(line) else {
            issues.push(issue(IssueCode::MalformedRow));
            continue;
        };
        let (Ok(m_month), Ok(m_day)) = (m[1].parse::<i8>(), m[2].parse::<i8>()) else {
            issues.push(issue(IssueCode::InvalidDate));
            continue;
        };
        // A December row on a January statement is last year's.
        let row_year = if m_month > month { year - 1 } else { year };
        let Ok(day) = Date::new(row_year, m_month, m_day) else {
            issues.push(issue(IssueCode::InvalidDate));
            continue;
        };
        let Some(settled) = money::parse(&m[8].replace(',', ""), true) else {
            issues.push(issue(IssueCode::InvalidAmount));
            continue;
        };
        match settled {
            0 => issues.push(issue(IssueCode::ZeroAmount)),
            s if s < 0 => issues.push(issue(IssueCode::UnsupportedDirection)),
            s => {
                let description = m[5].trim().to_owned();
                rows.push(Row {
                    at: day.at(0, 0, 0, 0),
                    has_time: false,
                    payee: Some(description.clone()),
                    description,
                    item: None,
                    provider_type: None,
                    payment_method: Some(format!("招商银行信用卡({})", &m[7])),
                    amount: -s,
                    currency: default_currency.to_uppercase(),
                    kind: Kind::Expense,
                    category_hint: None,
                    reference: None,
                });
            }
        }
    }
    (rows, issues, candidates)
}
