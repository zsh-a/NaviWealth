use super::*;
use crate::{
    daily,
    models::EntryFlag,
    planning,
    repos::{journal_repository as journal, settings_repository},
    wealth,
};
use chrono::Datelike;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ReconciliationStatus {
    Review,
    Confirmed,
    Undone,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Reconciliation {
    pub id: String,
    pub account_id: String,
    pub currency: String,
    /// Inclusive civil date; actual balance refers to the end of this date.
    pub date: i64,
    #[serde(with = "super::decimal")]
    pub before: Decimal,
    #[serde(with = "super::decimal")]
    /// Signed ledger balance: assets positive, amounts owed negative.
    pub actual: Decimal,
    #[serde(with = "super::decimal")]
    pub difference: Decimal,
    pub note: String,
    pub status: ReconciliationStatus,
    pub journal_id: Option<String>,
    pub journal_hlc: Option<String>,
}
pub fn reconciliations(conn: &Connection, owner: &str) -> Result<Vec<Reconciliation>> {
    list(conn, owner, "reconciliation")?
        .into_iter()
        .map(|(_, v)| decode(v))
        .collect()
}
pub fn create_reconciliation(
    conn: &mut Connection,
    st: &MutationStamper,
    account_id: &str,
    date: i64,
    actual: Decimal,
    note: &str,
) -> Result<Reconciliation> {
    if date.rem_euclid(86400) != 0 || chrono::DateTime::from_timestamp(date, 0).is_none() {
        return Err(invalid("请选择有效对账日期"));
    }
    let until = date
        .checked_add(86400)
        .ok_or_else(|| invalid("日期超出范围"))?;
    let tx = conn.savepoint()?;
    let a = owned_account(&tx, &st.owner_user_id, account_id)?;
    let before = balance_at(&tx, &st.owner_user_id, account_id, until)?;
    let r = Reconciliation {
        id: lifeos::ids::new_id(),
        account_id: account_id.into(),
        currency: a.currency,
        date,
        before,
        actual,
        difference: actual
            .checked_sub(before)
            .ok_or_else(|| invalid("对账差额超出范围"))?,
        note: note.trim().into(),
        status: ReconciliationStatus::Review,
        journal_id: None,
        journal_hlc: None,
    };
    put(&tx, st, &r.id, "reconciliation", encode(&r)?)?;
    tx.commit()?;
    Ok(r)
}
pub fn confirm_reconciliation(
    conn: &mut Connection,
    st: &MutationStamper,
    id: &str,
) -> Result<Reconciliation> {
    let tx = conn.savepoint()?;
    let mut r: Reconciliation = decode(get(&tx, &st.owner_user_id, id, "reconciliation")?)?;
    if r.status == ReconciliationStatus::Confirmed {
        return Ok(r);
    }
    if r.status == ReconciliationStatus::Undone {
        return Err(invalid("此对账已撤销，请重新对账"));
    }
    let a = owned_account(&tx, &st.owner_user_id, &r.account_id)?;
    if a.currency != r.currency
        || balance_at(&tx, &st.owner_user_id, &r.account_id, r.date + 86400)? != r.before
    {
        return Err(invalid("对账期间的账本已变化，请重新生成差额预览"));
    }
    if !r.difference.is_zero() {
        if r.note.trim().is_empty() {
            return Err(invalid("差额调整需要填写原因"));
        }
        let equity = accounts::get(
            &tx,
            &crate::system_accounts::system_account_id(&st.owner_user_id, "equity:adjustments"),
        )?
        .filter(|a| {
            a.sync.owner_user_id == st.owner_user_id
                && a.sync.deleted_at.is_none()
                && a.side == AccountSide::Equity
        })
        .ok_or_else(|| invalid("调整权益账户不可用"))?;
        let build = crate::builders::EntryBuild {
            entry: crate::builders::EntryDraft {
                date: r.date,
                settled_on: None,
                narration: format!("对账调整：{}", r.note),
                payee: None,
                flag: EntryFlag::Padding,
                tag_ids: vec![format!("reconciliation:{id}")],
            },
            postings: vec![
                crate::builders::PostingDraft {
                    position: 0,
                    account_id: r.account_id.clone(),
                    units: r.difference,
                    unit: r.currency.clone(),
                    cost: None,
                    price: None,
                },
                crate::builders::PostingDraft {
                    position: 1,
                    account_id: equity.id,
                    units: -r.difference,
                    unit: r.currency.clone(),
                    cost: None,
                    price: None,
                },
            ],
        };
        let fx = |c: &Connection, f: &str, t: &str, d: i64| crate::fx::rate_at(c, f, t, d);
        let entry = journal::create_in_transaction(&tx, st, &fx, &r.currency, build, None)?;
        r.journal_id = Some(entry.entry.id);
        r.journal_hlc = Some(entry.entry.sync.hlc);
    }
    r.status = ReconciliationStatus::Confirmed;
    put(&tx, st, id, "reconciliation", encode(&r)?)?;
    tx.commit()?;
    Ok(r)
}
pub fn undo_reconciliation(conn: &mut Connection, st: &MutationStamper, id: &str) -> Result<()> {
    let tx = conn.savepoint()?;
    let mut r: Reconciliation = decode(get(&tx, &st.owner_user_id, id, "reconciliation")?)?;
    if r.status == ReconciliationStatus::Undone {
        return Ok(());
    }
    if r.status != ReconciliationStatus::Confirmed {
        return Err(invalid("此对账尚未确认"));
    }
    if let Some(jid) = &r.journal_id {
        let entry = journal::get(&tx, jid)?
            .filter(|e| e.entry.sync.owner_user_id == st.owner_user_id)
            .ok_or_else(|| invalid("差额记录无法访问"))?;
        if entry.entry.sync.deleted_at.is_none()
            && Some(&entry.entry.sync.hlc) != r.journal_hlc.as_ref()
        {
            return Err(invalid("差额记录已修改，请先单独核对"));
        }
        delete_owned_journal(&tx, st, jid)?;
    }
    r.status = ReconciliationStatus::Undone;
    put(&tx, st, id, "reconciliation", encode(&r)?)?;
    tx.commit()?;
    Ok(())
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueKind {
    ImportReview,
    Reconciliation,
    DataIntegrity,
    RecurringDue,
    LiabilityDue,
    DcaDue,
    MissingPrice,
    MissingFx,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueDisposition {
    Dismissed,
    Resolved,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct IssueNote {
    pub issue_key: String,
    pub disposition: IssueDisposition,
    pub note: String,
    pub recorded_at: i64,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FinancialIssue {
    pub key: String,
    pub kind: IssueKind,
    pub title: String,
    pub detail: String,
    pub due: Option<i64>,
    pub blocking: bool,
    pub note: Option<IssueNote>,
}
fn issue(
    key: String,
    kind: IssueKind,
    title: String,
    detail: String,
    due: Option<i64>,
    blocking: bool,
) -> FinancialIssue {
    FinancialIssue {
        key,
        kind,
        title,
        detail,
        due,
        blocking,
        note: None,
    }
}
/// Deterministic current problems and actual unresolved due items. Saved notes
/// never erase the underlying issue or claim the source problem was fixed.
pub fn financial_inbox(conn: &Connection, owner: &str, as_of: i64) -> Result<Vec<FinancialIssue>> {
    let mut issues = Vec::new();
    for s in imports(conn, owner)? {
        if s.status == ImportStatus::Review {
            let rows = import_rows(conn, owner, &s.id)?;
            if !rows
                .iter()
                .any(|r| r.draft.as_ref().is_none_or(|d| d.date <= as_of))
            {
                continue;
            }
            let pending = rows.iter().filter(|r| !r.reviewed).count();
            issues.push(issue(
                format!("import:{}", s.id),
                IssueKind::ImportReview,
                "账单等待复核".into(),
                format!(
                    "{}：{} 行，{} 行待复核；确认后才计入账本",
                    s.source_name, s.row_count, pending
                ),
                None,
                true,
            ));
        }
    }
    for r in reconciliations(conn, owner)? {
        if r.status == ReconciliationStatus::Review && !r.difference.is_zero() && r.date <= as_of {
            issues.push(issue(
                format!("reconciliation:{}", r.id),
                IssueKind::Reconciliation,
                "对账差额尚未处理".into(),
                format!("{} {}；需要确认调整或重新对账", r.difference, r.currency),
                Some(r.date),
                true,
            ));
        }
    }
    for e in journal::list_owned(conn, owner, None, Some(as_of.saturating_add(1)))? {
        let mut broken = e.postings.is_empty();
        for p in &e.postings {
            let account = accounts::get(conn, &p.account_id)?;
            if p.sync.owner_user_id != owner
                || account
                    .is_none_or(|a| a.sync.owner_user_id != owner || a.sync.deleted_at.is_some())
            {
                broken = true;
            }
        }
        if broken {
            issues.push(issue(
                format!("entry:{}", e.entry.id),
                IssueKind::DataIntegrity,
                "分录关联缺失".into(),
                "记录的账户或分录无法完整读取，请核对原始记录".into(),
                Some(e.entry.date),
                true,
            ));
        }
    }
    // Include every unresolved saved obligation, even when it is older than a
    // convenient lookback window. Monthly evidence also includes completed items.
    let first = planning_start(conn, owner, as_of)?;
    for action in planning::planning_actions(conn, owner, first, as_of.saturating_add(31 * 86400))?
    {
        if action.state != planning::OccurrenceState::Due {
            continue;
        }
        let (key, kind) = match &action.source {
            planning::PlanningSource::Recurring { template_id, due } => (
                format!("recurring:{template_id}:{due}"),
                IssueKind::RecurringDue,
            ),
            planning::PlanningSource::Liability {
                liability_id,
                index,
            } => (
                format!("liability:{liability_id}:{index}"),
                IssueKind::LiabilityDue,
            ),
            planning::PlanningSource::Dca { plan_id, due } => {
                (format!("dca:{plan_id}:{due}"), IssueKind::DcaDue)
            }
            planning::PlanningSource::LiabilityOpening { .. } => continue,
        };
        issues.push(issue(
            key,
            kind,
            action.name,
            format!("待确认 {} {}；尚未计入流水", action.amount, action.currency),
            Some(action.due),
            action.due <= as_of,
        ));
    }
    let base = settings_repository::base_currency(conn)?;
    let snapshot = wealth::snapshot(conn, owner, as_of, &base)?;
    let mut price_assets = std::collections::BTreeSet::new();
    for holding in snapshot
        .holdings
        .iter()
        .filter(|h| h.market_price.is_none() && !h.quantity.is_zero())
    {
        if !price_assets.insert(holding.asset_id.clone()) {
            continue;
        }
        issues.push(issue(
            format!("price:{}", holding.asset_id),
            IssueKind::MissingPrice,
            format!("{} 缺少价格", holding.name),
            "补录实际价格及日期后才能得到完整净资产估值".into(),
            None,
            true,
        ));
    }
    for currency in snapshot.missing_fx {
        issues.push(issue(
            format!("fx:{currency}"),
            IssueKind::MissingFx,
            "估值缺少汇率".into(),
            format!("{currency} 无法换算到 {base}；净资产暂不完整"),
            None,
            true,
        ));
    }
    let notes = list(conn, owner, "issue_note")?
        .into_iter()
        .map(|(_, v)| decode::<IssueNote>(v))
        .collect::<Result<Vec<_>>>()?;
    for issue in &mut issues {
        issue.note = notes.iter().find(|n| n.issue_key == issue.key).cloned();
    }
    issues.sort_by_key(|i| (!i.blocking, i.due.unwrap_or(i64::MAX), i.key.clone()));
    Ok(issues)
}
pub fn note_financial_issue(
    conn: &mut Connection,
    st: &MutationStamper,
    key: &str,
    disposition: IssueDisposition,
    note: &str,
    as_of: i64,
) -> Result<()> {
    if note.trim().is_empty() || note.chars().count() > 2000 {
        return Err(invalid("请填写不超过 2000 字的处理说明"));
    }
    let tx = conn.savepoint()?;
    if !financial_inbox(&tx, &st.owner_user_id, as_of)?
        .iter()
        .any(|i| i.key == key)
    {
        return Err(invalid("当前问题已不存在，请刷新收件箱"));
    }
    let id = format!("issue-note:{}", digest(&[&st.owner_user_id, key]));
    let n = IssueNote {
        issue_key: key.into(),
        disposition,
        note: note.trim().into(),
        recorded_at: lifeos::ids::now_millis().div_euclid(1000),
    };
    put(&tx, st, &id, "issue_note", encode(&n)?)?;
    tx.commit()?;
    Ok(())
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CloseStep {
    ImportReview,
    InboxClear,
    AccountReconcile,
    RunwayReview,
    ActionReview,
}
impl CloseStep {
    pub const ALL: [Self; 5] = [
        Self::ImportReview,
        Self::InboxClear,
        Self::AccountReconcile,
        Self::RunwayReview,
        Self::ActionReview,
    ];
    pub fn label(self) -> &'static str {
        match self {
            Self::ImportReview => "账单复核",
            Self::InboxClear => "财务收件箱",
            Self::AccountReconcile => "账户对账",
            Self::RunwayReview => "现金跑道复盘",
            Self::ActionReview => "行动复盘",
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CloseStepStatus {
    Blocked,
    Ready,
    Verified,
    Overridden,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CloseStepReview {
    pub step: CloseStep,
    pub source_digest: String,
    pub evidence: Value,
    pub note: String,
    pub override_reason: Option<String>,
    pub reviewed_at: i64,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CloseStepReadiness {
    pub step: CloseStep,
    pub status: CloseStepStatus,
    pub blockers: Vec<String>,
    pub source_digest: String,
    pub evidence: Value,
    pub review: Option<CloseStepReview>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonthClose {
    pub id: String,
    pub month: String,
    pub steps: Vec<CloseStepReview>,
    pub snapshot: Option<MonthlySnapshot>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonthlyAccount {
    pub account_id: String,
    pub name: String,
    pub currency: String,
    #[serde(with = "super::decimal")]
    pub balance: Decimal,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonthlyTotals {
    pub currency: String,
    #[serde(with = "super::decimal")]
    pub income: Decimal,
    #[serde(with = "super::decimal")]
    pub expense: Decimal,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonthlySnapshot {
    pub month: String,
    pub from: i64,
    pub until: i64,
    pub closed_at: i64,
    pub accounts: Vec<MonthlyAccount>,
    pub totals: Vec<MonthlyTotals>,
    pub base_currency: String,
    #[serde(with = "super::optional_decimal")]
    pub net_worth: Option<Decimal>,
    pub missing_prices: Vec<String>,
    pub missing_fx: Vec<String>,
    pub previous_month: Option<String>,
    #[serde(with = "super::optional_decimal")]
    pub previous_net_worth: Option<Decimal>,
    #[serde(with = "super::optional_decimal")]
    pub net_worth_change: Option<Decimal>,
    pub ledger_digest: String,
    pub reviews: Vec<CloseStepReview>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct MonthCloseReadiness {
    pub month: String,
    pub ready: bool,
    pub steps: Vec<CloseStepReadiness>,
    pub saved_snapshot: Option<MonthlySnapshot>,
}
fn month_bounds(month: &str) -> Result<(i64, i64)> {
    let d = chrono::NaiveDate::parse_from_str(&format!("{month}-01"), "%Y-%m-%d")
        .map_err(|_| invalid("月份须为 YYYY-MM"))?;
    if d.format("%Y-%m").to_string() != month {
        return Err(invalid("月份须为 YYYY-MM"));
    }
    let next = if d.month() == 12 {
        chrono::NaiveDate::from_ymd_opt(d.year() + 1, 1, 1)
    } else {
        chrono::NaiveDate::from_ymd_opt(d.year(), d.month() + 1, 1)
    }
    .ok_or_else(|| invalid("月份超出范围"))?;
    Ok((
        d.and_hms_opt(0, 0, 0).unwrap().and_utc().timestamp(),
        next.and_hms_opt(0, 0, 0).unwrap().and_utc().timestamp(),
    ))
}
fn close_id(owner: &str, month: &str) -> String {
    format!("month-close:{}", digest(&[owner, month]))
}
pub fn month_closes(conn: &Connection, owner: &str) -> Result<Vec<MonthClose>> {
    list(conn, owner, "month_close")?
        .into_iter()
        .map(|(_, v)| decode(v))
        .collect()
}
fn close_or_new(conn: &Connection, owner: &str, month: &str) -> Result<MonthClose> {
    month_bounds(month)?;
    let id = close_id(owner, month);
    let found = list(conn, owner, "month_close")?
        .into_iter()
        .find(|(key, _)| key == &id);
    match found {
        Some((_, v)) => decode(v),
        None => Ok(MonthClose {
            id,
            month: month.into(),
            steps: Vec::new(),
            snapshot: None,
        }),
    }
}
fn ledger_evidence(conn: &Connection, owner: &str, until: i64) -> Result<Value> {
    Ok(Value::Array(
        journal::list_owned(conn, owner, None, Some(until))?
            .into_iter()
            .map(|e| {
                json!([
                    e.entry.id,
                    e.entry.sync.hlc,
                    e.postings
                        .iter()
                        .map(|p| json!([p.id, p.sync.hlc]))
                        .collect::<Vec<_>>()
                ])
            })
            .collect(),
    ))
}
pub fn month_close_readiness(
    conn: &Connection,
    owner: &str,
    month: &str,
) -> Result<MonthCloseReadiness> {
    let (from, until) = month_bounds(month)?;
    let saved = close_or_new(conn, owner, month)?;
    let mut steps = Vec::new();
    let ledger = ledger_evidence(conn, owner, until)?;
    let inbox = financial_inbox(conn, owner, until - 1)?;
    for step in CloseStep::ALL {
        let mut blockers = Vec::new();
        let evidence = match step {
            CloseStep::ImportReview => {
                let sessions = imports(conn, owner)?;
                let mut relevant = Vec::new();
                for s in sessions {
                    let rows = import_rows(conn, owner, &s.id)?;
                    let touches = rows.iter().any(|r| {
                        r.draft
                            .as_ref()
                            .is_some_and(|d| d.date >= from && d.date < until)
                    });
                    let unknown = rows.iter().any(|r| r.draft.is_none());
                    if s.status == ImportStatus::Review && (touches || unknown) {
                        blockers.push(format!("{} 尚未确认或撤销", s.source_name));
                    }
                    if touches || unknown {
                        relevant.push(json!([s.id, s.status, rows]));
                    }
                }
                json!({"sessions":relevant})
            }
            CloseStep::InboxClear => {
                for i in &inbox {
                    if i.blocking {
                        blockers.push(i.title.clone());
                    }
                }
                json!({"issues":inbox})
            }
            CloseStep::AccountReconcile => {
                let reconciles = reconciliations(conn, owner)?;
                let mut evidence = Vec::new();
                for (a, _) in daily::list_accounts(conn, owner, true)? {
                    let balance = balance_at(conn, owner, &a.id, until)?;
                    if a.archived && balance.is_zero() {
                        continue;
                    }
                    let r = reconciles.iter().find(|r| {
                        r.account_id == a.id
                            && r.date == until - 86400
                            && r.status == ReconciliationStatus::Confirmed
                            && r.actual == balance
                    });
                    if r.is_none() {
                        blockers.push(format!("{} 需要月末对账", a.name));
                    }
                    evidence.push(json!({"account_id":a.id,"currency":a.currency,"balance":balance.to_string(),"reconciliation":r}));
                }
                let base = settings_repository::base_currency(conn)?;
                let valuation = wealth::snapshot(conn, owner, until - 1, &base)?;
                let valuation = json!({"as_of":valuation.as_of,"base_currency":valuation.base_currency,"net_worth":valuation.net_worth.map(|v|v.to_string()),"missing_prices":valuation.missing_prices,"missing_fx":valuation.missing_fx,"holdings":valuation.holdings.iter().map(|h|json!({"asset_id":h.asset_id,"account_id":h.account_id,"quantity":h.quantity.to_string(),"market_price":h.market_price.map(|v|v.to_string()),"price_as_of":h.price_as_of,"base_value":h.base_value.map(|v|v.to_string())})).collect::<Vec<_>>()});
                json!({"accounts":evidence,"ledger":ledger,"valuation":valuation})
            }
            CloseStep::RunwayReview => {
                let base = settings_repository::base_currency(conn)?;
                let r = planning::runway(conn, owner, until, &base, 90)?;
                if r.min_balance < Decimal::ZERO {
                    blockers
                        .push("未来 90 天计划现金余额出现缺口，需要调整计划或说明处理方案".into());
                }
                json!({"as_of":r.as_of,"currency":r.currency,"horizon_days":r.horizon_days,"starting_balance":r.starting_balance.to_string(),"predicted_balance":r.predicted_balance.to_string(),"min_balance":r.min_balance.to_string(),"flows":r.flows.iter().map(|f|json!([f.source_id,f.due,f.amount.to_string(),f.currency])).collect::<Vec<_>>(),"assumptions":r.assumptions})
            }
            CloseStep::ActionReview => {
                let actions = planning::planning_actions(
                    conn,
                    owner,
                    planning_start(conn, owner, from)?,
                    until,
                )?;
                for a in &actions {
                    if a.state == planning::OccurrenceState::Due {
                        blockers.push(format!("{} 尚未处理", a.name));
                    }
                }
                json!({"as_of":until-1,"actions":actions.into_iter().map(|a|json!({"source":a.source,"name":a.name,"due":a.due,"amount":a.amount.to_string(),"currency":a.currency,"state":a.state,"journal_id":a.journal_id})).collect::<Vec<_>>()})
            }
        };
        let source_digest = digest(&[&evidence.to_string()]);
        let review = saved
            .steps
            .iter()
            .find(|r| r.step == step && r.source_digest == source_digest)
            .cloned();
        let status = if let Some(r) = &review {
            if r.override_reason.is_some() {
                CloseStepStatus::Overridden
            } else if blockers.is_empty() {
                CloseStepStatus::Verified
            } else {
                CloseStepStatus::Blocked
            }
        } else if blockers.is_empty() {
            CloseStepStatus::Ready
        } else {
            CloseStepStatus::Blocked
        };
        steps.push(CloseStepReadiness {
            step,
            status,
            blockers,
            source_digest,
            evidence,
            review,
        });
    }
    let ready = steps.iter().all(|s| {
        matches!(
            s.status,
            CloseStepStatus::Verified | CloseStepStatus::Overridden
        )
    });
    Ok(MonthCloseReadiness {
        month: month.into(),
        ready,
        steps,
        saved_snapshot: saved.snapshot,
    })
}
/// Persist the exact real-source evidence the user reviewed. A blocked step
/// requires a separate explicit reason; a mere "verified" click cannot clear it.
pub fn review_month_close_step(
    conn: &mut Connection,
    st: &MutationStamper,
    month: &str,
    step: CloseStep,
    note: &str,
    override_reason: Option<&str>,
) -> Result<MonthCloseReadiness> {
    if note.trim().is_empty() {
        return Err(invalid("请记录本步骤的复盘结论"));
    }
    if override_reason.is_some_and(|s| s.trim().is_empty()) {
        return Err(invalid("覆盖阻塞需要填写明确原因"));
    }
    let tx = conn.savepoint()?;
    let readiness = month_close_readiness(&tx, &st.owner_user_id, month)?;
    let current = readiness
        .steps
        .into_iter()
        .find(|s| s.step == step)
        .ok_or_else(|| invalid("月结步骤不存在"))?;
    if !current.blockers.is_empty() && override_reason.is_none() {
        return Err(invalid("此步骤存在真实阻塞，请先处理，或明确填写覆盖原因"));
    }
    let mut close = close_or_new(&tx, &st.owner_user_id, month)?;
    close.steps.retain(|r| r.step != step);
    close.steps.push(CloseStepReview {
        step,
        source_digest: current.source_digest,
        evidence: current.evidence,
        note: note.trim().into(),
        override_reason: override_reason.map(|s| s.trim().into()),
        reviewed_at: lifeos::ids::now_millis().div_euclid(1000),
    });
    put(&tx, st, &close.id, "month_close", encode(&close)?)?;
    tx.commit()?;
    month_close_readiness(conn, &st.owner_user_id, month)
}
pub fn finalize_month_close(
    conn: &mut Connection,
    st: &MutationStamper,
    month: &str,
) -> Result<MonthlySnapshot> {
    let tx = conn.savepoint()?;
    let (from, until) = month_bounds(month)?;
    if until > lifeos::ids::now_millis().div_euclid(1000) {
        return Err(invalid("本月尚未结束，不能生成已完成月结"));
    }
    let readiness = month_close_readiness(&tx, &st.owner_user_id, month)?;
    if !readiness.ready {
        return Err(invalid("请完成五个步骤，真实阻塞须处理或填写明确覆盖原因"));
    }
    let base = settings_repository::base_currency(&tx)?;
    let wealth = wealth::snapshot(&tx, &st.owner_user_id, until - 1, &base)?;
    let accounts = daily::list_accounts(&tx, &st.owner_user_id, true)?
        .into_iter()
        .map(|(a, _)| {
            Ok(MonthlyAccount {
                balance: balance_at(&tx, &st.owner_user_id, &a.id, until)?,
                account_id: a.id,
                name: a.name,
                currency: a.currency,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    let totals = daily::monthly_totals(&tx, &st.owner_user_id, from, until)?
        .into_iter()
        .map(|(currency, income, expense)| MonthlyTotals {
            currency,
            income,
            expense,
        })
        .collect();
    let previous_date = chrono::DateTime::from_timestamp(from - 1, 0)
        .ok_or_else(|| invalid("月份无效"))?
        .format("%Y-%m")
        .to_string();
    let previous = close_or_new(&tx, &st.owner_user_id, &previous_date)?.snapshot;
    let previous_net_worth = previous
        .as_ref()
        .filter(|p| p.base_currency == base)
        .and_then(|p| p.net_worth);
    let change = wealth
        .net_worth
        .zip(previous_net_worth)
        .and_then(|(a, b)| a.checked_sub(b));
    let snapshot = MonthlySnapshot {
        month: month.into(),
        from,
        until,
        closed_at: lifeos::ids::now_millis().div_euclid(1000),
        accounts,
        totals,
        base_currency: base,
        net_worth: wealth.net_worth,
        missing_prices: wealth.missing_prices,
        missing_fx: wealth.missing_fx,
        previous_month: previous.as_ref().map(|p| p.month.clone()),
        previous_net_worth,
        net_worth_change: change,
        ledger_digest: digest(&[&ledger_evidence(&tx, &st.owner_user_id, until)?.to_string()]),
        reviews: readiness
            .steps
            .into_iter()
            .filter_map(|s| s.review)
            .collect(),
    };
    let mut close = close_or_new(&tx, &st.owner_user_id, month)?;
    close.snapshot = Some(snapshot.clone());
    put(&tx, st, &close.id, "month_close", encode(&close)?)?;
    tx.commit()?;
    Ok(snapshot)
}

/// Narrow ownership seam for the daily record projection. Callers must route
/// edits and deletion to the reconciliation operation to preserve its evidence.
pub fn source_for_entry(
    conn: &Connection,
    owner: &str,
    journal_id: &str,
) -> Result<Option<String>> {
    Ok(reconciliations(conn, owner)?
        .into_iter()
        .find(|r| {
            r.status == ReconciliationStatus::Confirmed
                && r.journal_id.as_deref() == Some(journal_id)
        })
        .map(|r| r.id))
}

fn planning_start(conn: &Connection, owner: &str, fallback: i64) -> Result<i64> {
    let mut first = fallback;
    for r in planning::list_recurring(conn, owner)? {
        if !r.data.paused {
            first = first.min(r.data.first_due);
        }
    }
    for r in planning::dca_plans(conn, owner)? {
        if !r.data.paused {
            first = first.min(r.data.first_due);
        }
    }
    for l in planning::liabilities(conn, owner)? {
        first = first.min(l.data.terms.first_due);
    }
    Ok(first)
}

/// Discard an unconfirmed preview; confirmed adjustments require undo instead.
pub fn cancel_reconciliation(conn: &mut Connection, st: &MutationStamper, id: &str) -> Result<()> {
    let tx = conn.savepoint()?;
    let mut r: Reconciliation = decode(get(&tx, &st.owner_user_id, id, "reconciliation")?)?;
    if r.status == ReconciliationStatus::Confirmed {
        return Err(invalid("已确认对账请使用撤销调整"));
    }
    r.status = ReconciliationStatus::Undone;
    put(&tx, st, id, "reconciliation", encode(&r)?)?;
    tx.commit()?;
    Ok(())
}
