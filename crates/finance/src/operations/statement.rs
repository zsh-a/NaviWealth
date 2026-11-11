use super::*;
use crate::{
    builders,
    daily::{self, RecordKind},
    repos::journal_repository as journal,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// UTF-8 CSV contract: exact header, positive decimal magnitude, ISO civil date.
/// direction is `expense` or `income`; currency is an uppercase ISO-like code.
pub const STATEMENT_CSV_HEADER: &str = "date,amount,currency,direction,counterparty,note";
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RowReview {
    pub date: i64,
    #[serde(with = "super::decimal")]
    pub signed_amount: Decimal,
    pub currency: String,
    pub counterparty: String,
    pub note: String,
    pub category_id: Option<String>,
    pub excluded: bool,
    /// An explicit reason permits a genuine repeated purchase with identical evidence.
    pub duplicate_override_reason: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ParsedRow {
    pub row_number: u32,
    pub draft: Option<RowReview>,
    pub problems: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ParsedStatement {
    pub rows: Vec<ParsedRow>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ImportStatus {
    Review,
    Confirmed,
    Undone,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ImportSession {
    pub id: String,
    pub source_name: String,
    pub source_account_id: Option<String>,
    pub created_at: i64,
    pub status: ImportStatus,
    pub row_count: usize,
    pub confirmation: Option<ImportConfirmation>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ImportRow {
    pub id: String,
    pub session_id: String,
    pub row_number: u32,
    pub draft: Option<RowReview>,
    pub problems: Vec<String>,
    pub reviewed: bool,
    pub evidence_hash: Option<String>,
    pub duplicate_of: Option<String>,
    pub journal_id: Option<String>,
    pub journal_hlc: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct ImportConfirmation {
    pub created: usize,
    pub duplicates: usize,
    pub excluded: usize,
    pub entry_ids: Vec<String>,
}

fn csv_records(input: &str) -> Result<Vec<Vec<String>>> {
    if input.len() > 10_000_000 {
        return Err(invalid("CSV 超过 10MB，请分批导入"));
    }
    let mut records = Vec::new();
    let mut row = Vec::new();
    let mut value = String::new();
    let mut quoted = false;
    let mut after_quote = false;
    let mut it = input.trim_start_matches('\u{feff}').chars().peekable();
    while let Some(c) = it.next() {
        if quoted {
            if c == '"' {
                if it.peek() == Some(&'"') {
                    it.next();
                    value.push('"');
                } else {
                    quoted = false;
                    after_quote = true;
                }
            } else {
                value.push(c);
            }
            continue;
        }
        if after_quote && !matches!(c, ',' | '\n' | '\r') {
            return Err(invalid("CSV 引号闭合后只能接逗号或换行"));
        }
        match c {
            '"' if value.is_empty() && !after_quote => quoted = true,
            '"' => return Err(invalid("CSV 引号格式错误，请使用双引号包裹含逗号的字段")),
            ',' => {
                row.push(std::mem::take(&mut value));
                after_quote = false;
            }
            '\n' | '\r' => {
                if c == '\r' && it.peek() == Some(&'\n') {
                    it.next();
                }
                row.push(std::mem::take(&mut value));
                records.push(std::mem::take(&mut row));
                after_quote = false;
                if records.len() > 20_001 {
                    return Err(invalid("CSV 超过 20000 行，请分批导入"));
                }
            }
            _ => value.push(c),
        }
    }
    if quoted {
        return Err(invalid("CSV 引号未闭合，请检查导出文件"));
    }
    if !value.is_empty() || !row.is_empty() || after_quote {
        row.push(value);
        records.push(row);
    }
    Ok(records)
}
fn validate_review(d: &RowReview) -> Result<()> {
    if chrono::DateTime::from_timestamp(d.date, 0).is_none() || d.date.rem_euclid(86_400) != 0 {
        return Err(invalid("日期必须是有效的 UTC 民用日期"));
    }
    if d.signed_amount.is_zero() {
        return Err(invalid("金额不能为零"));
    }
    if lifeos::money::Currency::new(&d.currency).is_err()
        || d.currency != d.currency.trim().to_ascii_uppercase()
    {
        return Err(invalid("币种必须是有效的大写代码"));
    }
    if d.counterparty.chars().count() > 500 || d.note.chars().count() > 2000 {
        return Err(invalid("对方或备注过长，请缩短后重试"));
    }
    if d.duplicate_override_reason
        .as_ref()
        .is_some_and(|v| v.trim().is_empty())
    {
        return Err(invalid("保留重复行需要填写原因"));
    }
    Ok(())
}
pub fn parse_statement_csv(input: &str) -> Result<ParsedStatement> {
    let records = csv_records(input)?;
    let header = records.first().ok_or_else(|| invalid("CSV 文件为空"))?;
    if header.iter().map(|s| s.trim()).collect::<Vec<_>>()
        != STATEMENT_CSV_HEADER.split(',').collect::<Vec<_>>()
    {
        return Err(invalid(
            "CSV 表头须为 date,amount,currency,direction,counterparty,note",
        ));
    }
    let mut rows = Vec::new();
    for (i, cells) in records.into_iter().enumerate().skip(1) {
        if cells.iter().all(|s| s.trim().is_empty()) {
            continue;
        }
        let mut problems = Vec::new();
        let mut draft = None;
        if cells.len() != 6 {
            problems.push("应包含 6 列；含逗号的字段请加双引号".to_owned());
        } else {
            let date = chrono::NaiveDate::parse_from_str(cells[0].trim(), "%Y-%m-%d")
                .ok()
                .filter(|v| v.format("%Y-%m-%d").to_string() == cells[0].trim())
                .and_then(|v| v.and_hms_opt(0, 0, 0))
                .map(|v| v.and_utc().timestamp());
            if date.is_none() {
                problems.push("日期须为有效的 YYYY-MM-DD".to_owned());
            }
            let amount = Decimal::from_str_exact(cells[1].trim())
                .ok()
                .filter(|a| *a > Decimal::ZERO);
            if amount.is_none() {
                problems.push("amount 须为大于零的十进制金额，不含千位分隔符".to_owned());
            }
            let sign = match cells[3].trim() {
                "expense" => Some(-Decimal::ONE),
                "income" => Some(Decimal::ONE),
                _ => None,
            };
            if sign.is_none() {
                problems.push("direction 只能是 expense 或 income".to_owned());
            }
            let currency = cells[2].trim().to_owned();
            if lifeos::money::Currency::new(&currency).is_err()
                || currency != currency.to_ascii_uppercase()
            {
                problems.push("currency 须为有效大写币种代码".to_owned());
            }
            if let (Some(date), Some(amount), Some(sign)) = (date, amount, sign) {
                let d = RowReview {
                    date,
                    signed_amount: amount * sign,
                    currency,
                    counterparty: cells[4].trim().into(),
                    note: cells[5].trim().into(),
                    category_id: None,
                    excluded: false,
                    duplicate_override_reason: None,
                };
                if let Err(e) = validate_review(&d) {
                    problems.push(e.to_string());
                }
                if problems.is_empty() {
                    draft = Some(d);
                }
            }
        }
        rows.push(ParsedRow {
            row_number: (i + 1) as u32,
            draft,
            problems,
        });
    }
    if rows.is_empty() {
        return Err(invalid("CSV 没有可处理的数据行"));
    }
    Ok(ParsedStatement { rows })
}
/// The reliable export format is identical to the import contract.
pub fn export_statement_csv(rows: &[RowReview]) -> Result<String> {
    fn quote(s: &str) -> String {
        format!("\"{}\"", s.replace('"', "\"\""))
    }
    let mut result = format!("{STATEMENT_CSV_HEADER}\n");
    for d in rows {
        validate_review(d)?;
        let date = chrono::DateTime::from_timestamp(d.date, 0)
            .ok_or_else(|| invalid("日期无效"))?
            .format("%Y-%m-%d")
            .to_string();
        result.push_str(
            &[
                date,
                d.signed_amount.abs().normalize().to_string(),
                d.currency.clone(),
                if d.signed_amount < Decimal::ZERO {
                    "expense"
                } else {
                    "income"
                }
                .into(),
                quote(&d.counterparty),
                quote(&d.note),
            ]
            .join(","),
        );
        result.push('\n');
    }
    Ok(result)
}
pub fn create_import(
    conn: &mut Connection,
    st: &MutationStamper,
    source_name: &str,
    parsed: &ParsedStatement,
) -> Result<ImportSession> {
    if source_name.trim().is_empty() || source_name.chars().count() > 200 {
        return Err(invalid("请输入不超过 200 字的来源名称"));
    }
    if parsed.rows.is_empty() || parsed.rows.len() > 20_000 {
        return Err(invalid("导入批次须包含 1 至 20000 行"));
    }
    let tx = conn.savepoint()?;
    let id = lifeos::ids::new_id();
    let session = ImportSession {
        id: id.clone(),
        source_name: source_name.trim().into(),
        source_account_id: None,
        created_at: lifeos::ids::now_millis().div_euclid(1000),
        status: ImportStatus::Review,
        row_count: parsed.rows.len(),
        confirmation: None,
    };
    put(&tx, st, &id, "import_session", encode(&session)?)?;
    for source in &parsed.rows {
        if let Some(d) = &source.draft {
            validate_review(d)?;
        }
        let row = ImportRow {
            id: lifeos::ids::new_id(),
            session_id: id.clone(),
            row_number: source.row_number,
            draft: source.draft.clone(),
            problems: source.problems.clone(),
            reviewed: false,
            evidence_hash: None,
            duplicate_of: None,
            journal_id: None,
            journal_hlc: None,
        };
        put(&tx, st, &row.id, "import_row", encode(&row)?)?;
    }
    tx.commit()?;
    Ok(session)
}
pub fn imports(conn: &Connection, owner: &str) -> Result<Vec<ImportSession>> {
    list(conn, owner, "import_session")?
        .into_iter()
        .map(|(_, v)| decode(v))
        .collect()
}
pub fn import_session(conn: &Connection, owner: &str, id: &str) -> Result<ImportSession> {
    decode(get(conn, owner, id, "import_session")?)
}
pub fn import_rows(conn: &Connection, owner: &str, session_id: &str) -> Result<Vec<ImportRow>> {
    import_session(conn, owner, session_id)?;
    let mut result = Vec::new();
    for (_, v) in list(conn, owner, "import_row")? {
        let row: ImportRow = decode(v)?;
        if row.session_id == session_id {
            result.push(row);
        }
    }
    result.sort_by_key(|r| r.row_number);
    Ok(result)
}
pub fn assign_import_account(
    conn: &mut Connection,
    st: &MutationStamper,
    session_id: &str,
    account_id: &str,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let mut s = import_session(&tx, &st.owner_user_id, session_id)?;
    if s.status != ImportStatus::Review {
        return Err(invalid("已确认或撤销的批次不可更换账户"));
    }
    owned_account(&tx, &st.owner_user_id, account_id)?;
    s.source_account_id = Some(account_id.into());
    put(&tx, st, &s.id, "import_session", encode(&s)?)?;
    tx.commit()?;
    Ok(())
}
pub fn review_import_row(
    conn: &mut Connection,
    st: &MutationStamper,
    session_id: &str,
    row_id: &str,
    review: RowReview,
) -> Result<()> {
    validate_review(&review)?;
    let tx = conn.savepoint()?;
    let s = import_session(&tx, &st.owner_user_id, session_id)?;
    if s.status != ImportStatus::Review {
        return Err(invalid("此批次已结束，不能再修改"));
    }
    let mut row: ImportRow = decode(get(&tx, &st.owner_user_id, row_id, "import_row")?)?;
    if row.session_id != session_id {
        return Err(invalid("此行不属于当前导入批次"));
    }
    if !review.excluded {
        validate_category(&tx, &st.owner_user_id, &review)?;
    }
    row.draft = Some(review);
    row.reviewed = true;
    row.problems.clear();
    put(&tx, st, row_id, "import_row", encode(&row)?)?;
    tx.commit()?;
    Ok(())
}
/// Explicitly skip an invalid CSV row without fabricating corrected values.
pub fn exclude_import_row(
    conn: &mut Connection,
    st: &MutationStamper,
    session_id: &str,
    row_id: &str,
    reason: &str,
) -> Result<()> {
    if reason.trim().is_empty() {
        return Err(invalid("跳过问题行请填写原因"));
    }
    let tx = conn.savepoint()?;
    let s = import_session(&tx, &st.owner_user_id, session_id)?;
    if s.status != ImportStatus::Review {
        return Err(invalid("此批次已结束"));
    }
    let mut row: ImportRow = decode(get(&tx, &st.owner_user_id, row_id, "import_row")?)?;
    if row.session_id != session_id {
        return Err(invalid("此行不属于当前批次"));
    }
    if let Some(d) = &mut row.draft {
        d.excluded = true;
    }
    row.reviewed = true;
    row.problems = vec![format!("已跳过：{}", reason.trim())];
    put(&tx, st, row_id, "import_row", encode(&row)?)?;
    tx.commit()?;
    Ok(())
}
fn validate_category(conn: &Connection, owner: &str, d: &RowReview) -> Result<()> {
    let kind = if d.signed_amount < Decimal::ZERO {
        RecordKind::Expense
    } else {
        RecordKind::Income
    };
    let category = d
        .category_id
        .as_ref()
        .ok_or_else(|| invalid("每行须明确选择收支分类"))?;
    if !daily::categories(conn, owner, kind)?
        .iter()
        .any(|(id, _)| id == category)
    {
        return Err(invalid("分类不可用或与收支方向不符"));
    }
    Ok(())
}
fn canonical(owner: &str, account: &str, d: &RowReview) -> String {
    json!([
        owner,
        account,
        d.date,
        d.signed_amount.normalize().to_string(),
        d.currency,
        d.counterparty.trim().to_lowercase()
    ])
    .to_string()
}
fn create_daily(
    conn: &Connection,
    st: &MutationStamper,
    account: &str,
    d: &RowReview,
) -> Result<journal::EntryWithPostings> {
    validate_review(d)?;
    validate_category(conn, &st.owner_user_id, d)?;
    let a = owned_account(conn, &st.owner_user_id, account)?;
    if a.currency != d.currency {
        return Err(invalid("账单币种与来源账户不一致，请更正账户或行币种"));
    }
    let category = d
        .category_id
        .as_ref()
        .ok_or_else(|| invalid("请选择分类"))?;
    let build = if d.signed_amount < Decimal::ZERO {
        builders::expense(
            d.date,
            category,
            account,
            d.signed_amount.abs(),
            &d.currency,
            Some(d.counterparty.clone()),
            Some(&d.note),
            None,
            vec![],
        )?
    } else {
        builders::income(
            d.date,
            account,
            category,
            d.signed_amount,
            &d.currency,
            Some(d.counterparty.clone()),
            Some(&d.note),
            None,
            vec![],
        )?
    };
    let fx = |c: &Connection, f: &str, t: &str, date: i64| crate::fx::rate_at(c, f, t, date);
    journal::create_in_transaction(conn, st, &fx, &d.currency, build, None)
}
pub fn confirm_import(
    conn: &mut Connection,
    st: &MutationStamper,
    session_id: &str,
) -> Result<ImportConfirmation> {
    let tx = conn.savepoint()?;
    let mut session = import_session(&tx, &st.owner_user_id, session_id)?;
    if session.status == ImportStatus::Confirmed {
        return session
            .confirmation
            .ok_or_else(|| invalid("批次确认信息缺失"));
    }
    if session.status == ImportStatus::Undone {
        return Err(invalid("此批次已撤销，请创建新批次"));
    }
    let account = session
        .source_account_id
        .as_ref()
        .ok_or_else(|| invalid("请先明确选择账单来源账户"))?;
    owned_account(&tx, &st.owner_user_id, account)?;
    let rows = import_rows(&tx, &st.owner_user_id, session_id)?;
    if rows.len() != session.row_count || rows.iter().any(|r| !r.reviewed) {
        return Err(invalid("请逐行复核、分类或明确跳过所有问题行"));
    }
    let mut evidence = existing_evidence(&tx, &st.owner_user_id)?;
    let mut result = ImportConfirmation::default();
    for mut row in rows {
        let Some(d) = row.draft.as_ref().filter(|d| !d.excluded) else {
            result.excluded += 1;
            continue;
        };
        if !row.problems.is_empty() {
            result.excluded += 1;
            continue;
        }
        validate_category(&tx, &st.owner_user_id, d)?;
        let a = owned_account(&tx, &st.owner_user_id, account)?;
        if a.currency != d.currency {
            return Err(invalid("行币种与来源账户不一致"));
        }
        let key = canonical(&st.owner_user_id, account, d);
        let hash = digest(&[&key]);
        row.evidence_hash = Some(hash.clone());
        if let Some((_, duplicate)) = evidence
            .get(&hash)
            .and_then(|matches| matches.iter().find(|(k, _)| k == &key))
            && d.duplicate_override_reason.is_none()
        {
            row.duplicate_of = Some(duplicate.clone());
            result.duplicates += 1;
        } else {
            let entry = create_daily(&tx, st, account, d)?;
            row.journal_id = Some(entry.entry.id.clone());
            row.journal_hlc = Some(entry.entry.sync.hlc.clone());
            evidence
                .entry(hash)
                .or_default()
                .push((key, entry.entry.id.clone()));
            result.entry_ids.push(entry.entry.id);
            result.created += 1;
        }
        put(&tx, st, &row.id, "import_row", encode(&row)?)?;
    }
    session.status = ImportStatus::Confirmed;
    session.confirmation = Some(result.clone());
    put(&tx, st, session_id, "import_session", encode(&session)?)?;
    tx.commit()?;
    Ok(result)
}
pub fn undo_import(conn: &mut Connection, st: &MutationStamper, session_id: &str) -> Result<usize> {
    let tx = conn.savepoint()?;
    let mut s = import_session(&tx, &st.owner_user_id, session_id)?;
    if s.status == ImportStatus::Undone {
        return Ok(0);
    }
    if s.status != ImportStatus::Confirmed {
        return Err(invalid("仅已确认批次可以撤销"));
    }
    let rows = import_rows(&tx, &st.owner_user_id, session_id)?;
    validate_undo_receipts(&tx, &st.owner_user_id, &s, &rows)?;
    let mut removed = 0;
    for row in rows {
        if let Some(id) = row.journal_id {
            let active = journal::get(&tx, &id)?.is_some_and(|e| e.entry.sync.deleted_at.is_none());
            if active {
                delete_owned_journal(&tx, st, &id)?;
                removed += 1;
            }
        }
    }
    s.status = ImportStatus::Undone;
    put(&tx, st, session_id, "import_session", encode(&s)?)?;
    tx.commit()?;
    Ok(removed)
}

const INCOMPLETE_UNDO_RECEIPT: &str =
    "批次确认回执尚未完整同步，暂不能撤销。请等待同步完成后刷新；未撤销任何流水。";
/// A confirmed session can arrive before its rows and journal revisions during
/// row-state sync. Never delete a visible subset or close that batch lifecycle.
fn validate_undo_receipts(
    conn: &Connection,
    owner: &str,
    session: &ImportSession,
    rows: &[ImportRow],
) -> Result<()> {
    use std::collections::BTreeSet;
    let pending = || invalid(INCOMPLETE_UNDO_RECEIPT);
    let receipt = session.confirmation.as_ref().ok_or_else(pending)?;
    if session.row_count == 0
        || session.row_count > 20_000
        || rows.len() != session.row_count
        || rows
            .iter()
            .any(|r| !r.reviewed || r.session_id != session.id)
        || receipt
            .created
            .checked_add(receipt.duplicates)
            .and_then(|n| n.checked_add(receipt.excluded))
            != Some(session.row_count)
        || receipt.created != receipt.entry_ids.len()
    {
        return Err(pending());
    }
    let expected = receipt.entry_ids.iter().collect::<BTreeSet<_>>();
    if expected.len() != receipt.created || expected.iter().any(|id| id.is_empty()) {
        return Err(pending());
    }
    let mut actual = BTreeSet::new();
    let mut duplicate_count = 0usize;
    let mut excluded_count = 0usize;
    for row in rows {
        let excluded = row.draft.as_ref().is_none_or(|d| d.excluded) || !row.problems.is_empty();
        if excluded {
            if row.journal_id.is_some() || row.journal_hlc.is_some() || row.duplicate_of.is_some() {
                return Err(pending());
            }
            excluded_count += 1;
            continue;
        }
        if row.evidence_hash.as_ref().is_none_or(|v| v.is_empty()) {
            return Err(pending());
        }
        match (&row.journal_id, &row.journal_hlc, &row.duplicate_of) {
            (Some(id), Some(hlc), None) if !id.is_empty() && !hlc.is_empty() => {
                if !actual.insert(id) {
                    return Err(pending());
                }
            }
            (None, None, Some(duplicate)) if !duplicate.is_empty() => duplicate_count += 1,
            _ => return Err(pending()),
        }
    }
    if actual != expected
        || duplicate_count != receipt.duplicates
        || excluded_count != receipt.excluded
    {
        return Err(pending());
    }
    // Receipt completeness comes first. All subsequent checks are read-only and
    // must pass before the first ledger tombstone or lifecycle mutation.
    for row in rows {
        if let Some(id) = &row.journal_id {
            let entry = journal::get(conn, id)?
                .filter(|e| e.entry.sync.owner_user_id == owner)
                .ok_or_else(pending)?;
            if entry.entry.sync.deleted_at.is_none() {
                if Some(&entry.entry.sync.hlc) != row.journal_hlc.as_ref() {
                    return Err(invalid("批次中有记录已被修改，请单独核对，未撤销任何记录"));
                }
                if entry.postings.len() != 2
                    || entry.postings.iter().any(|p| {
                        p.sync.owner_user_id != owner || p.sync.hlc != entry.entry.sync.hlc
                    })
                {
                    return Err(pending());
                }
            }
        }
    }
    Ok(())
}
#[derive(Debug, Clone, PartialEq)]
pub struct ImportUndoReadiness {
    pub can_undo: bool,
    pub created: usize,
    pub message: String,
}
/// Read-only UI preflight; undo repeats the same checks inside its savepoint.
pub fn import_undo_readiness(
    conn: &Connection,
    owner: &str,
    session_id: &str,
) -> Result<ImportUndoReadiness> {
    let session = import_session(conn, owner, session_id)?;
    let created = session
        .confirmation
        .as_ref()
        .map(|r| r.created)
        .unwrap_or_default();
    if session.status != ImportStatus::Confirmed {
        return Ok(ImportUndoReadiness {
            can_undo: false,
            created,
            message: if session.status == ImportStatus::Undone {
                "此批次已经撤销，不会再次修改流水。"
            } else {
                "此批次尚未入账；放弃复核不会改变余额。"
            }
            .into(),
        });
    }
    let rows = import_rows(conn, owner, session_id)?;
    match validate_undo_receipts(conn, owner, &session, &rows) {
        Ok(()) => Ok(ImportUndoReadiness {
            can_undo: true,
            created,
            message: format!(
                "已核对完整 {} 行及 {} 笔批次流水。",
                session.row_count, created
            ),
        }),
        Err(FinanceError::InvalidData(message)) => Ok(ImportUndoReadiness {
            can_undo: false,
            created,
            message,
        }),
        Err(e) => Err(e),
    }
}

fn existing_evidence(
    conn: &Connection,
    owner: &str,
) -> Result<BTreeMap<String, Vec<(String, String)>>> {
    let mut evidence: BTreeMap<String, Vec<(String, String)>> = BTreeMap::new();
    for entry in journal::list_owned(conn, owner, None, None)? {
        let r = daily::record(conn, owner, &entry.entry.id)?;
        if matches!(r.kind, RecordKind::Expense | RecordKind::Income) {
            let d = RowReview {
                date: r.date,
                signed_amount: if r.kind == RecordKind::Expense {
                    -r.amount
                } else {
                    r.amount
                },
                currency: r.currency,
                counterparty: r.payee.unwrap_or_default(),
                note: String::new(),
                category_id: r.category_id,
                excluded: false,
                duplicate_override_reason: None,
            };
            let key = canonical(owner, &r.account_id, &d);
            evidence
                .entry(digest(&[&key]))
                .or_default()
                .push((key, r.id));
        }
    }
    Ok(evidence)
}
#[derive(Debug, Clone, PartialEq)]
pub struct ImportPreviewRow {
    pub row_id: String,
    pub row_number: u32,
    pub evidence_hash: Option<String>,
    pub duplicate_of: Option<String>,
    pub problems: Vec<String>,
    pub will_create: bool,
}
#[derive(Debug, Clone, PartialEq)]
pub struct ImportPreview {
    pub session_id: String,
    pub rows: Vec<ImportPreviewRow>,
    pub can_confirm: bool,
    pub created: usize,
    pub duplicates: usize,
    pub excluded: usize,
    pub blockers: Vec<String>,
}
/// Read-only confirmation preview. Duplicate evidence is checked again inside
/// the atomic commit, so newly imported records cannot race this preview.
pub fn preview_import(conn: &Connection, owner: &str, session_id: &str) -> Result<ImportPreview> {
    let s = import_session(conn, owner, session_id)?;
    let rows = import_rows(conn, owner, session_id)?;
    let mut result = ImportPreview {
        session_id: session_id.into(),
        rows: Vec::new(),
        can_confirm: false,
        created: 0,
        duplicates: 0,
        excluded: 0,
        blockers: Vec::new(),
    };
    if s.status != ImportStatus::Review {
        result.blockers.push("批次已结束".into());
    }
    let account = s
        .source_account_id
        .as_ref()
        .map(|id| owned_account(conn, owner, id))
        .transpose();
    let account = match account {
        Ok(Some(a)) => Some(a),
        _ => {
            result.blockers.push("请选择有效来源账户".into());
            None
        }
    };
    let mut evidence = existing_evidence(conn, owner)?;
    if rows.len() != s.row_count {
        result
            .blockers
            .push("批次行数据尚未完整，请稍后重试".into());
    }
    for row in rows {
        let mut p = ImportPreviewRow {
            row_id: row.id.clone(),
            row_number: row.row_number,
            evidence_hash: None,
            duplicate_of: None,
            problems: Vec::new(),
            will_create: false,
        };
        if !row.reviewed {
            p.problems.push("此行尚未复核".into());
        }
        if row.reviewed
            && (row.draft.is_none()
                || row.draft.as_ref().is_some_and(|d| d.excluded)
                || !row.problems.is_empty())
        {
            result.excluded += 1;
            result.rows.push(p);
            continue;
        }
        if let Some(d) = row.draft.as_ref() {
            if let Err(e) = validate_review(d).and_then(|_| validate_category(conn, owner, d)) {
                p.problems.push(e.to_string());
            }
            if let Some(a) = &account {
                if a.currency != d.currency {
                    p.problems.push("币种与来源账户不一致".into());
                }
                let key = canonical(owner, &a.id, d);
                let hash = digest(&[&key]);
                p.evidence_hash = Some(hash.clone());
                if let Some((_, id)) = evidence
                    .get(&hash)
                    .and_then(|items| items.iter().find(|(k, _)| k == &key))
                    && d.duplicate_override_reason.is_none()
                {
                    p.duplicate_of = Some(id.clone());
                    result.duplicates += 1;
                } else if p.problems.is_empty() {
                    p.will_create = true;
                    result.created += 1;
                    evidence
                        .entry(hash)
                        .or_default()
                        .push((key, format!("row:{}", row.id)));
                }
            }
        } else {
            p.problems.extend(row.problems);
        }
        result.rows.push(p);
    }
    result.can_confirm =
        result.blockers.is_empty() && result.rows.iter().all(|r| r.problems.is_empty());
    Ok(result)
}
pub fn cancel_import(conn: &mut Connection, st: &MutationStamper, session_id: &str) -> Result<()> {
    let tx = conn.savepoint()?;
    let mut s = import_session(&tx, &st.owner_user_id, session_id)?;
    if s.status == ImportStatus::Confirmed {
        return Err(invalid("已入账批次请使用批次撤销"));
    }
    s.status = ImportStatus::Undone;
    put(&tx, st, session_id, "import_session", encode(&s)?)?;
    tx.commit()?;
    Ok(())
}
