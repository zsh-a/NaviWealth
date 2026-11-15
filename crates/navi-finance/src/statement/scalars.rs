//! Cells of delimited statements: splitting, cleaning, header keys, dates
//! and amounts. Ported from the Flutter client's
//! `delimited_ingest_scalars.dart`, keeping its behavior on the fixtures.

use std::sync::LazyLock;

use jiff::civil::{Date, DateTime};
use regex::Regex;

use crate::money::{self, Minor};

static HAS_TIME: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d{1,2}:\d{2}").unwrap());
static CHINESE_DATE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(\d{4})年(\d{1,2})月(\d{1,2})日?").unwrap());
static NUMERIC_DATE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})").unwrap());
static TIME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(\d{1,2}):(\d{2})(?::(\d{2}))?").unwrap());
static HEADER_SEPARATORS: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[\s_\-：:]+").unwrap());
static TEXT_SEPARATORS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"[\s_\-：:·,，/()（）&]+").unwrap());

/// Whether a raw date cell carries a time of day.
pub fn has_time(raw: &str) -> bool {
    HAS_TIME.is_match(raw)
}

/// Lines a statement carries around its table: blank, `#` comments and
/// `----------------` banners.
pub fn is_preamble(line: &str) -> bool {
    let text = line.trim();
    text.is_empty() || text.starts_with('#') || text.starts_with("----------------")
}

/// The delimiter of the first line that is not preamble: a tab, `;` when
/// there is no comma, else `,`.
pub fn delimiter(lines: &[&str]) -> char {
    let sample = lines
        .iter()
        .find(|line| !is_preamble(line))
        .or(lines.first())
        .copied()
        .unwrap_or_default();
    if sample.contains('\t') {
        '\t'
    } else if sample.contains(';') && !sample.contains(',') {
        ';'
    } else {
        ','
    }
}

/// The cells of `line`, honoring double quotes (`""` is a quote).
pub fn split_row(line: &str, delimiter: char) -> Vec<String> {
    let mut cells = Vec::new();
    let mut cell = String::new();
    let mut quoted = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '"' {
            if quoted && chars.peek() == Some(&'"') {
                cell.push('"');
                chars.next();
            } else {
                quoted = !quoted;
            }
        } else if c == delimiter && !quoted {
            cells.push(cell.trim().to_owned());
            cell.clear();
        } else {
            cell.push(c);
        }
    }
    cells.push(cell.trim().to_owned());
    cells
}

/// A cell without byte-order marks, zero-width spaces, quotes or the
/// leading backticks and apostrophes exports use to keep numbers as text.
pub fn clean(value: &str) -> String {
    let text: String = value
        .chars()
        .filter(|c| !matches!(c, '\u{feff}' | '\u{200b}' | '"'))
        .collect();
    text.trim()
        .trim_start_matches(|c: char| c == '`' || c == '\'' || c.is_whitespace())
        .trim()
        .to_owned()
}

/// A header cell as a lookup key: lower case, no separators, ASCII
/// parentheses.
pub fn header_key(value: &str) -> String {
    HEADER_SEPARATORS
        .replace_all(&clean(value).to_lowercase(), "")
        .replace('（', "(")
        .replace('）', ")")
}

/// Text for keyword checks: lower case without separators.
pub fn normalized(value: &str) -> String {
    TEXT_SEPARATORS
        .replace_all(&value.to_lowercase(), "")
        .into_owned()
}

/// An opaque provider reference, `None` for placeholders.
pub fn reference(raw: Option<&str>) -> Option<String> {
    let value = raw?.trim();
    let placeholder =
        ["", "-", "--", "/", "—", "n/a", "null"].contains(&value.to_lowercase().as_str());
    (!placeholder).then(|| value.to_owned())
}

/// The date (and time, when written) of a statement cell: `2026-07-10
/// 12:30:01`, `2026/7/10`, `2026年7月10日`, or month-first `7/10/26`.
pub fn date_time(value: &str) -> Option<DateTime> {
    let cleaned = clean(value);
    if cleaned.is_empty() {
        return None;
    }
    let (year, month, day) = if let Some(m) = CHINESE_DATE.captures(&cleaned) {
        (num(&m[1])?, num(&m[2])?, num(&m[3])?)
    } else {
        let m = NUMERIC_DATE.captures(&cleaned)?;
        let (a, b, c) = (num(&m[1])?, num(&m[2])?, num(&m[3])?);
        if a > 31 {
            (a, b, c)
        } else {
            (if c < 100 { 2000 + c } else { c }, a, b)
        }
    };
    let date = Date::new(
        i16::try_from(year).ok()?,
        i8::try_from(month).ok()?,
        i8::try_from(day).ok()?,
    )
    .ok()?;
    let Some(time) = TIME.captures(&cleaned) else {
        return Some(date.at(0, 0, 0, 0));
    };
    let hour = num(&time[1])?;
    let minute = num(&time[2])?;
    let second = time.get(3).map_or(Some(0), |s| num(s.as_str()))?;
    if hour > 23 || minute > 59 || second > 59 {
        return None;
    }
    Some(date.at(hour as i8, minute as i8, second as i8, 0))
}

fn num(text: &str) -> Option<i32> {
    text.parse().ok()
}

/// The signed minor units of an amount cell (`¥1,234.50`, `(12.00)`,
/// `-3.5`); `None` for placeholders and anything not exact.
pub fn amount(value: Option<&str>) -> Option<Minor> {
    let text = clean(value?);
    if text.is_empty() || ["/", "--", "-"].contains(&text.as_str()) {
        return None;
    }
    let negative = text.starts_with('-') || (text.starts_with('(') && text.ends_with(')'));
    let digits: String = text
        .chars()
        .filter(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    let signed = if negative {
        format!("-{digits}")
    } else {
        digits
    };
    money::parse(&signed, true)
}

#[cfg(test)]
mod tests {
    use jiff::civil::date;

    use super::*;

    #[test]
    fn rows_split_on_unquoted_delimiters() {
        assert_eq!(
            split_row(r#"a,"纸巾,家庭装", "say ""hi""" ,"#, ','),
            ["a", "纸巾,家庭装", r#"say "hi""#, ""]
        );
        assert_eq!(delimiter(&["# note", "a\tb"]), '\t');
        assert_eq!(delimiter(&["a;b"]), ';');
        assert_eq!(delimiter(&["a;b,c"]), ',');
        assert!(is_preamble(
            "----------------支付宝交易明细列表----------------"
        ));
    }

    #[test]
    fn cells_and_headers_are_cleaned() {
        assert_eq!(clean("\u{feff}`'12.50\""), "12.50");
        assert_eq!(header_key(" 金额（元） "), "金额(元)");
        assert_eq!(header_key("收/支"), "收/支");
        assert_eq!(header_key("Transaction_Date"), "transactiondate");
        assert_eq!(normalized("还款 - 入账(人民币)"), "还款入账人民币");
        assert_eq!(reference(Some(" N/A ")), None);
        assert_eq!(reference(Some("trade-1")), Some("trade-1".into()));
    }

    #[test]
    fn dates_parse_in_the_statement_shapes() {
        assert_eq!(
            date_time("2026-07-10 12:30:01"),
            Some(date(2026, 7, 10).at(12, 30, 1, 0))
        );
        assert_eq!(date_time("2026/7/1"), Some(date(2026, 7, 1).at(0, 0, 0, 0)));
        assert_eq!(
            date_time("2026年7月10日 08:05"),
            Some(date(2026, 7, 10).at(8, 5, 0, 0))
        );
        assert_eq!(date_time("7/10/26"), Some(date(2026, 7, 10).at(0, 0, 0, 0)));
        assert_eq!(date_time("2026-02-30"), None);
        assert_eq!(date_time("2026-07-10 25:00"), None);
        assert_eq!(date_time("交易成功"), None);
        assert!(has_time("2026-07-10 12:30") && !has_time("2026-07-10"));
    }

    #[test]
    fn amounts_parse_exactly() {
        assert_eq!(amount(Some("¥1,234.50")), Some(123_450));
        assert_eq!(amount(Some("(12.00)")), Some(-1200));
        assert_eq!(amount(Some("-3.5")), Some(-350));
        assert_eq!(amount(Some("--")), None);
        assert_eq!(amount(Some("1.005")), None);
        assert_eq!(amount(None), None);
    }
}
