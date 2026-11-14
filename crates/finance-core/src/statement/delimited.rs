//! Delimited statements (Alipay and WeChat Pay CSV, or a converted XLSX):
//! the header row names the columns; each row becomes an expense or income
//! row, or an issue with its line. Ported from the Flutter client's
//! `csv_ingest_parser.dart`, which the corpus fixtures pin. Refunds,
//! transfers and "not counted" rows are issues here; the import decides
//! what a double-entry ledger makes of them later.

use super::{Issue, IssueCode, Kind, Row, scalars};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Col {
    Date,
    Description,
    Payee,
    Amount,
    Expense,
    Income,
    Currency,
    Direction,
    Status,
    Type,
    PaymentMethod,
    TransactionId,
    MerchantOrderId,
}

fn column(key: &str) -> Option<Col> {
    Some(match key {
        "date" | "日期" | "交易日期" | "交易时间" | "交易创建时间" | "付款时间" | "支付时间"
        | "入账日期" | "记账日期" | "账务日期" | "time" | "postdate" | "transactiondate" => {
            Col::Date
        }
        "description" | "desc" | "narration" | "摘要" | "备注" | "描述" | "商品" | "商品名称"
        | "商品说明" | "交易摘要" | "交易说明" | "用途" | "附言" => {
            Col::Description
        }
        "payee" | "merchant" | "商家" | "交易对方" | "对方" | "对方户名" | "商户名称"
        | "收款方" | "付款方" => Col::Payee,
        "amount" | "金额" | "金额(元)" | "发生额" | "交易金额" | "交易金额(元)" | "人民币金额"
        | "本币金额" => Col::Amount,
        "支出" | "支出金额" | "借方金额" | "借方发生额" | "取出" | "转出金额" | "付款金额"
        | "消费金额" => Col::Expense,
        "收入" | "收入金额" | "贷方金额" | "贷方发生额" | "存入" | "转入金额" | "收款金额" => {
            Col::Income
        }
        "currency" | "货币" | "币种" | "币别" => Col::Currency,
        "收/支" | "收支" | "收入/支出" | "借贷方向" | "交易方向" => Col::Direction,
        "状态" | "交易状态" | "当前状态" => Col::Status,
        "类型" | "交易类型" | "交易分类" | "业务类型" => Col::Type,
        "支付方式" | "付款方式" | "收/付款方式" | "交易渠道" | "账户" => {
            Col::PaymentMethod
        }
        "交易单号" | "交易订单号" | "交易号" | "流水号" | "transactionid" | "reference" => {
            Col::TransactionId
        }
        "商户单号" | "商家订单号" => Col::MerchantOrderId,
        _ => return None,
    })
}

/// Columns by index, ascending: a header pins at least a date and an amount.
type Mapping = Vec<(usize, Col)>;

fn mapping(cells: &[String]) -> Option<Mapping> {
    let found: Mapping = cells
        .iter()
        .enumerate()
        .filter_map(|(i, cell)| column(&scalars::header_key(cell)).map(|col| (i, col)))
        .collect();
    let has = |col: Col| found.iter().any(|(_, c)| *c == col);
    (has(Col::Date) && (has(Col::Amount) || has(Col::Expense) || has(Col::Income))).then_some(found)
}

/// The rows of a delimited statement, numbered as lines of `raw`.
pub(super) fn parse(raw: &str, default_currency: &str) -> (Vec<Row>, Vec<Issue>, usize) {
    let lines: Vec<(usize, &str)> = raw
        .lines()
        .enumerate()
        .filter(|(_, line)| !line.trim().is_empty())
        .map(|(i, line)| (i + 1, line.trim()))
        .collect();
    if lines.is_empty() {
        return (Vec::new(), Vec::new(), 0);
    }
    let texts: Vec<&str> = lines.iter().map(|(_, text)| *text).collect();
    let delimiter = scalars::delimiter(&texts);
    let header = texts
        .iter()
        .enumerate()
        .find_map(|(i, line)| mapping(&scalars::split_row(line, delimiter)).map(|m| (i, m)));
    let (start, columns) = match header {
        Some((i, m)) => (i + 1, m),
        // No header: date, description, amount, currency by position.
        None => (
            0,
            vec![
                (0, Col::Date),
                (1, Col::Description),
                (2, Col::Amount),
                (3, Col::Currency),
            ],
        ),
    };
    let mut rows = Vec::new();
    let mut issues = Vec::new();
    let mut candidates = 0;
    for &(number, line) in &lines[start..] {
        if scalars::is_preamble(line) {
            continue;
        }
        candidates += 1;
        let cells = scalars::split_row(line, delimiter);
        match row(&cells, &columns, default_currency) {
            Ok(row) => rows.push(row),
            Err(code) => issues.push(Issue { line: number, code }),
        }
    }
    (rows, issues, candidates)
}

fn row(cells: &[String], columns: &Mapping, default_currency: &str) -> Result<Row, IssueCode> {
    let cell = |col: Col| -> Option<String> {
        columns
            .iter()
            .filter(|(_, c)| *c == col)
            .filter_map(|(i, _)| cells.get(*i))
            .map(|v| scalars::clean(v))
            .find(|v| !v.is_empty())
    };
    let raw_date = cell(Col::Date);
    let at = raw_date
        .as_deref()
        .and_then(scalars::date_time)
        .ok_or(IssueCode::InvalidDate)?;
    if ignored_status(cell(Col::Status).as_deref()) {
        return Err(IssueCode::IgnoredStatus);
    }
    let direction = cell(Col::Direction);
    let expense = scalars::amount(cell(Col::Expense).as_deref());
    let income = scalars::amount(cell(Col::Income).as_deref());
    let amount = scalars::amount(cell(Col::Amount).as_deref());
    let payee = cell(Col::Payee);
    let item = cell(Col::Description);
    let provider_type = cell(Col::Type);
    let payment_method = cell(Col::PaymentMethod);
    let mut parts: Vec<&str> = Vec::new();
    for part in [&payee, &item, &provider_type, &payment_method]
        .into_iter()
        .flatten()
    {
        if !part.is_empty() && !parts.contains(&part.as_str()) {
            parts.push(part);
        }
    }
    let description = parts.join(" · ");
    if unsupported(direction.as_deref(), &description) {
        return Err(IssueCode::UnsupportedDirection);
    }
    let (kind, minor) =
        resolve(amount, expense, income, direction.as_deref()).ok_or(IssueCode::InvalidAmount)?;
    if minor == 0 {
        return Err(IssueCode::ZeroAmount);
    }
    let currency = cell(Col::Currency)
        .unwrap_or_else(|| default_currency.to_owned())
        .trim()
        .to_uppercase();
    let reference = scalars::reference(cell(Col::TransactionId).as_deref()).or_else(|| {
        scalars::reference(cell(Col::MerchantOrderId).as_deref()).map(|id| format!("merchant:{id}"))
    });
    let magnitude = minor.checked_abs().ok_or(IssueCode::InvalidAmount)?;
    Ok(Row {
        at,
        has_time: raw_date.as_deref().is_some_and(scalars::has_time),
        description: if description.is_empty() {
            "未命名交易".into()
        } else {
            description.clone()
        },
        payee,
        item,
        provider_type,
        payment_method,
        amount: if kind == Kind::Income {
            magnitude
        } else {
            -magnitude
        },
        currency: if currency.is_empty() {
            default_currency.to_uppercase()
        } else {
            currency
        },
        kind,
        category_hint: (kind == Kind::Income).then(|| income_hint(&description)),
        reference,
    })
}

fn ignored_status(status: Option<&str>) -> bool {
    let Some(status) = status else {
        return false;
    };
    let s: String = status.split_whitespace().collect();
    [
        "失败",
        "关闭",
        "撤销",
        "取消",
        "全额退款",
        "已退款",
        "退款成功",
    ]
    .iter()
    .any(|word| s.contains(word))
}

fn compact(text: Option<&str>) -> String {
    text.map(|t| t.split_whitespace().collect())
        .unwrap_or_default()
}

fn has_word(text: &str, word: &str) -> bool {
    text.split(|c: char| !c.is_alphanumeric())
        .any(|w| w == word)
}

fn unsupported(direction: Option<&str>, description: &str) -> bool {
    let text = description.to_lowercase();
    if text.contains("退款")
        || has_word(&text, "refund")
        || text.contains("转账")
        || has_word(&text, "transfer")
    {
        return true;
    }
    let dir = compact(direction);
    if dir.contains("收入") || dir == "收" {
        return false;
    }
    dir.contains("不计") || dir.contains("其他") || dir.contains("退款")
}

fn resolve(
    amount: Option<i64>,
    expense: Option<i64>,
    income: Option<i64>,
    direction: Option<&str>,
) -> Option<(Kind, i64)> {
    let dir = compact(direction);
    if !dir.is_empty() {
        if dir.contains("收入") || dir == "收" {
            return amount.or(income).map(|a| (Kind::Income, a.abs()));
        }
        if dir.contains("不计") || dir.contains("其他") || dir.contains("退款") {
            return None;
        }
        if dir.contains("支出") || dir == "支" {
            return amount.or(expense).map(|a| (Kind::Expense, a.abs()));
        }
    }
    if let Some(e) = expense.filter(|e| *e != 0) {
        return Some((Kind::Expense, e.abs()));
    }
    if amount.is_none_or(|a| a == 0)
        && let Some(i) = income.filter(|i| *i != 0)
    {
        return Some((Kind::Income, i.abs()));
    }
    let amount = amount?;
    if amount > 0 && income.is_some_and(|i| i.abs() == amount) {
        return Some((Kind::Income, amount));
    }
    // Without a direction, a positive amount has always meant an expense.
    Some((Kind::Expense, amount.abs()))
}

fn income_hint(description: &str) -> &'static str {
    let text = description.to_lowercase();
    if text.contains("工资") || text.contains("salary") {
        "salary"
    } else if text.contains("利息") || text.contains("结息") || text.contains("interest") {
        "interest"
    } else if text.contains("股息") || text.contains("分红") || text.contains("dividend") {
        "dividend"
    } else {
        "other"
    }
}
