//! Statement parsing: an Alipay CSV, a WeChat Pay CSV or XLSX, or a CMB
//! credit-card statement's text becomes rows (expenses and income, each
//! with its payee, item, provider category, payment method and reference)
//! and issues (lines that were skipped, with a stable reason). Every
//! candidate line is accounted for. Nothing here touches the journal.

mod cmb;
mod delimited;
pub mod scalars;
mod source;

use jiff::civil::DateTime;

pub use source::{MAX_FILE_BYTES, StatementError, decode};

/// Who issued a statement.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Provider {
    Alipay,
    WechatPay,
    CmbCreditCard,
    /// A delimited statement of no known provider, read by its headers.
    Generic,
}

impl Provider {
    /// A stable key, kept with imported transactions and mapping rules.
    pub fn key(self) -> &'static str {
        match self {
            Provider::Alipay => "alipay",
            Provider::WechatPay => "wechat",
            Provider::CmbCreditCard => "cmb-credit",
            Provider::Generic => "generic",
        }
    }
}

/// Money in or out.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Kind {
    Expense,
    Income,
    Refund,
    TransferIn,
    TransferOut,
    NeedsDirection,
}

/// Why a candidate line did not become a row.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IssueCode {
    InvalidDate,
    IgnoredStatus,
    UnsupportedDirection,
    InvalidAmount,
    ZeroAmount,
    MalformedRow,
}

impl IssueCode {
    /// The name the corpus fixtures use.
    pub fn name(self) -> &'static str {
        match self {
            IssueCode::InvalidDate => "invalidDate",
            IssueCode::IgnoredStatus => "ignoredStatus",
            IssueCode::UnsupportedDirection => "unsupportedDirection",
            IssueCode::InvalidAmount => "invalidAmount",
            IssueCode::ZeroAmount => "zeroAmount",
            IssueCode::MalformedRow => "malformedRow",
        }
    }
}

/// A skipped line: its number in the statement's text, and why.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Issue {
    pub line: usize,
    pub code: IssueCode,
}

/// One money movement on a statement.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    /// When it happened, as written (midnight when only a day is).
    pub at: DateTime,
    pub has_time: bool,
    /// Payee, item, provider category and payment method, joined by ` · `.
    pub description: String,
    pub payee: Option<String>,
    pub item: Option<String>,
    /// The provider's own category or type (`餐饮美食`, `商户消费`).
    pub provider_type: Option<String>,
    /// How it was paid (`余额`, `花呗`, `招商银行信用卡(1234)`).
    pub payment_method: Option<String>,
    /// Signed minor units: negative out, positive in.
    pub amount: i64,
    pub currency: String,
    pub kind: Kind,
    /// A category the statement makes unambiguous (`dining`, `salary`).
    pub category_hint: Option<&'static str>,
    /// The provider's transaction id, or `merchant:<order id>`.
    pub reference: Option<String>,
}

/// What a statement came to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Report {
    pub provider: Provider,
    pub rows: Vec<Row>,
    pub issues: Vec<Issue>,
    /// Lines that looked like transactions.
    pub candidates: usize,
}

impl Report {
    /// Whether every candidate line is a row or an issue.
    pub fn accounts_for_every_candidate(&self) -> bool {
        self.rows.len() + self.issues.len() == self.candidates
    }
}

/// The provider of a statement's text.
pub fn detect(raw: &str) -> Provider {
    let compact: String = raw.split_whitespace().collect();
    let alipay = compact.contains("支付宝交易记录明细")
        || compact.contains("交易号,商家订单号,交易创建时间,付款时间")
        || compact.contains("支付宝支付科技有限公司电子客户回单")
        || (compact.contains("交易时间,交易分类,交易对方")
            && compact.contains("商品说明,收/支,金额,收/付款方式")
            && compact.contains("交易订单号,商家订单号"));
    if alipay {
        Provider::Alipay
    } else if compact.contains("微信支付账单明细")
        || compact.contains("交易时间,交易类型,交易对方,商品,收/支")
    {
        Provider::WechatPay
    } else if cmb::is_statement(raw) {
        Provider::CmbCreditCard
    } else {
        Provider::Generic
    }
}

/// The rows of a statement's text, in `default_currency` unless a row
/// says otherwise.
pub fn parse(raw: &str, default_currency: &str) -> Report {
    parse_mode(raw, default_currency, false)
}

/// Ledger review keeps refunds and transfers for explicit account correction.
/// The legacy parser remains the frozen corpus compatibility contract.
pub fn review(raw: &str, default_currency: &str) -> Report {
    parse_mode(raw, default_currency, true)
}

fn parse_mode(raw: &str, default_currency: &str, review: bool) -> Report {
    let provider = detect(raw);
    let (rows, issues, candidates) = match provider {
        Provider::CmbCreditCard => cmb::parse(raw, default_currency, review),
        // Alipay's payment time, not its order creation time, is when the
        // money moved.
        Provider::Alipay => {
            let (rows, issues, candidates) = delimited::parse(
                &raw.replacen("交易创建时间", "交易创建时间(平台)", 1),
                default_currency,
                review,
            );
            (
                rows.into_iter().map(alipay_hint).collect(),
                issues,
                candidates,
            )
        }
        Provider::WechatPay | Provider::Generic => delimited::parse(raw, default_currency, review),
    };
    Report {
        provider,
        rows,
        issues,
        candidates,
    }
}

/// The statement in a file's `bytes` (CSV or text in UTF-8 or GB18030, or
/// an XLSX workbook).
pub fn parse_file(bytes: &[u8], default_currency: &str) -> Result<Report, StatementError> {
    Ok(parse(&decode(bytes)?, default_currency))
}

/// Alipay categories with one clear meaning; broad ones (`充值缴费`) stay
/// unset rather than confidently wrong.
fn alipay_hint(mut row: Row) -> Row {
    let hint = |part: &str| match part.trim() {
        "餐饮美食" => Some("dining"),
        "日用百货" => Some("groceries"),
        "住房物业" => Some("housing"),
        "数码电器" => Some("shopping"),
        "文化休闲" => Some("entertainment"),
        "其他" => Some("other"),
        _ => None,
    };
    if let Some(found) = row.description.split(" · ").find_map(hint) {
        row.category_hint = Some(found);
    }
    row
}
