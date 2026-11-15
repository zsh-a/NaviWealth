//! Durable, local statement review. Only confirmation writes the journal.
use super::{Candidate, Rules, Status};
use crate::{
    account::Account,
    journal::{self, Entry, Source, Transaction},
    repository::{self, Error},
    statement::{self, Kind},
};
use navi_storage::sqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const SCHEMA: &str = "CREATE TABLE finance_import_drafts(singleton INTEGER PRIMARY KEY CHECK(singleton = 1), body TEXT NOT NULL);";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Correction {
    pub kind: Kind,
    pub category: Account,
    pub other: Option<Account>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Draft {
    pub name: String,
    pub text: String,
    pub rules: Rules,
    pub selected: BTreeMap<usize, bool>,
    pub corrections: BTreeMap<usize, Correction>,
    /// Exact state reviewed, for optimistic confirmation against fresh truth.
    pub journal: Vec<Transaction>,
    pub baseline_rules: Rules,
}

impl Draft {
    pub fn review(&self) -> Vec<Candidate> {
        self.review_report(&statement::review(&self.text, "CNY"))
    }
    pub fn review_report(&self, report: &statement::Report) -> Vec<Candidate> {
        let mut rows = super::prepare(report, &self.rules, &self.journal);
        for (i, c) in rows.iter_mut().enumerate() {
            if let Some(edit) = self.corrections.get(&i) {
                c.row.kind = edit.kind;
                c.category = crate::currency::Currency::parse(&c.row.currency)
                    .map(|currency| edit.category.in_currency(currency))
                    .unwrap_or_else(|| edit.category.clone());
                let own = self
                    .rules
                    .methods
                    .get(report.provider.key())
                    .and_then(|m| m.get(&c.method));
                c.transaction = own.and_then(|own| {
                    if own.currency().code() != c.row.currency {
                        return None;
                    }
                    if matches!(edit.kind, Kind::TransferIn | Kind::TransferOut) {
                        let other = edit.other.as_ref()?;
                        let entry = Entry {
                            id: format!("{}:{}", report.provider.key(), c.id),
                            at: c.row.at,
                            payee: c.row.payee.clone().unwrap_or_default(),
                            note: c.row.item.clone().unwrap_or_default(),
                            source: Source::Statement {
                                provider: report.provider.key().into(),
                                id: c.id.clone(),
                            },
                        };
                        let amount = c.row.amount.checked_abs()?;
                        if edit.kind == Kind::TransferIn {
                            journal::transfer(entry, other, own, amount).ok()
                        } else {
                            journal::transfer(entry, own, other, amount).ok()
                        }
                    } else {
                        super::transaction(report.provider, &c.row, &c.id, own, &c.category)
                    }
                });
            }
            if c.status != Status::Duplicate {
                c.status = if crate::currency::Currency::parse(&c.row.currency).is_none()
                    || c.transaction.is_none()
                    || (c.row.kind == Kind::Refund && !self.corrections.contains_key(&i))
                {
                    if self
                        .rules
                        .methods
                        .get(report.provider.key())
                        .is_none_or(|m| !m.contains_key(&c.method))
                    {
                        Status::NeedsAccount
                    } else {
                        Status::NeedsAttention
                    }
                } else if c
                    .transaction
                    .as_ref()
                    .is_some_and(|t| super::looks_kept(t, &self.journal))
                {
                    Status::PossibleDuplicate
                } else {
                    Status::New
                };
            }
        }
        rows
    }
    pub fn is_selected(&self, index: usize, row: &Candidate) -> bool {
        row.transaction.is_some()
            && matches!(row.status, Status::New | Status::PossibleDuplicate)
            && self.selected.get(&index).copied().unwrap_or(row.selected())
    }
    pub fn refresh(&mut self, connection: &Connection) -> Result<(), Error> {
        self.journal = repository::transactions(connection)?;
        let latest = repository::rules(connection)?;
        let mut merged = latest.clone();
        for (provider, methods) in &self.rules.methods {
            for (method, account) in methods {
                if self
                    .baseline_rules
                    .methods
                    .get(provider)
                    .and_then(|m| m.get(method))
                    != Some(account)
                {
                    merged
                        .methods
                        .entry(provider.clone())
                        .or_default()
                        .insert(method.clone(), account.clone());
                }
            }
        }
        for (payee, account) in &self.rules.payees {
            if self.baseline_rules.payees.get(payee) != Some(account) {
                merged.payees.insert(payee.clone(), account.clone());
            }
        }
        self.rules = merged;
        self.baseline_rules = latest;
        // A refreshed possible duplicate always needs an explicit choice again.
        for (i, c) in self.review().iter().enumerate() {
            if c.status != Status::New {
                self.selected.remove(&i);
            }
        }
        Ok(())
    }
}

/// A file parsed and checked away from the UI thread.
pub struct Prepared {
    pub draft: Draft,
    pub report: statement::Report,
    pub rows: Vec<Candidate>,
}
pub fn read_file(
    name: &str,
    bytes: &[u8],
    rules: Rules,
    journal: Vec<Transaction>,
) -> Result<Prepared, Error> {
    if bytes.starts_with(b"%PDF") || name.to_ascii_lowercase().ends_with(".pdf") {
        return Err(Error::Invalid(
            "PDF unsupported; export CSV, XLSX or statement text",
        ));
    }
    let text = statement::decode(bytes).map_err(|_| Error::Invalid("unreadable statement file"))?;
    let report = statement::review(&text, "CNY");
    if report.candidates == 0 || !report.accounts_for_every_candidate() {
        return Err(Error::Invalid("no statement rows found"));
    }
    let draft = Draft {
        name: name.into(),
        text,
        rules: rules.clone(),
        selected: BTreeMap::new(),
        corrections: BTreeMap::new(),
        journal,
        baseline_rules: rules,
    };
    let rows = draft.review_report(&report);
    Ok(Prepared {
        draft,
        report,
        rows,
    })
}
pub fn keep_prepared(connection: &Connection, prepared: &Prepared) -> Result<(), Error> {
    if active(connection)?.is_some() {
        return Err(Error::Invalid("resume or discard the current import first"));
    }
    connection.execute(
        "INSERT INTO finance_import_drafts VALUES(1,?1)",
        [serde_json::to_string(&prepared.draft)?],
    )?;
    Ok(())
}
pub fn create(connection: &Connection, name: &str, bytes: &[u8]) -> Result<Draft, Error> {
    let prepared = read_file(
        name,
        bytes,
        repository::rules(connection)?,
        repository::transactions(connection)?,
    )?;
    keep_prepared(connection, &prepared)?;
    Ok(prepared.draft)
}
pub fn active(connection: &Connection) -> Result<Option<Draft>, Error> {
    let mut query = connection.prepare("SELECT singleton,body FROM finance_import_drafts")?;
    let mut rows = query.query([])?;
    let Some(row) = rows.next()? else {
        return Ok(None);
    };
    if row.get::<_, i64>(0)? != 1 {
        return Err(Error::Invalid("import draft key"));
    }
    let draft: Draft = serde_json::from_str(&row.get::<_, String>(1)?)?;
    if rows.next()?.is_some() {
        return Err(Error::Invalid("multiple import drafts"));
    }
    check(&draft)?;
    Ok(Some(draft))
}
fn check(draft: &Draft) -> Result<(), Error> {
    if draft.text.len() > statement::MAX_FILE_BYTES * 4 || draft.name.len() > 4096 {
        return Err(Error::Invalid("import draft size"));
    }
    let report = statement::review(&draft.text, "CNY");
    if report.candidates == 0
        || !report.accounts_for_every_candidate()
        || draft
            .selected
            .keys()
            .chain(draft.corrections.keys())
            .any(|i| *i >= report.rows.len())
    {
        return Err(Error::Invalid("import draft rows"));
    }
    for t in &draft.journal {
        t.validate()?;
    }
    Ok(())
}
pub fn save(connection: &Connection, draft: &Draft) -> Result<(), Error> {
    let source: Option<String> = connection
        .query_row(
            "SELECT body FROM finance_import_drafts WHERE singleton=1",
            [],
            |r| r.get(0),
        )
        .optional()?;
    let unchanged = source
        .as_deref()
        .and_then(|s| serde_json::from_str::<Draft>(s).ok())
        .is_some_and(|old| old.text == draft.text && old.name == draft.name);
    if !unchanged {
        check(draft)?;
    }
    connection.execute("INSERT INTO finance_import_drafts VALUES(1,?1) ON CONFLICT(singleton) DO UPDATE SET body=excluded.body",[serde_json::to_string(draft)?])?;
    Ok(())
}
pub(crate) fn rename_account(
    connection: &Connection,
    old: &Account,
    new: &Account,
) -> Result<(), Error> {
    let exists: i64 = connection.query_row(
        "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='finance_import_drafts'",
        [],
        |r| r.get(0),
    )?;
    if exists == 0 {
        return Ok(());
    }
    let Some(mut draft) = active(connection)? else {
        return Ok(());
    };
    for rules in [&mut draft.rules, &mut draft.baseline_rules] {
        for methods in rules.methods.values_mut() {
            for a in methods.values_mut() {
                if a == old {
                    *a = new.clone()
                }
            }
        }
    }
    for edit in draft.corrections.values_mut() {
        if edit.other.as_ref() == Some(old) {
            edit.other = Some(new.clone())
        }
    }
    for t in &mut draft.journal {
        for p in &mut t.postings {
            if &p.account == old {
                p.account = new.clone()
            }
        }
    }
    save(connection, &draft)
}
pub fn discard(connection: &Connection) -> Result<(), Error> {
    connection.execute("DELETE FROM finance_import_drafts", [])?;
    Ok(())
}
pub fn validate(connection: &Connection) -> Result<(), Error> {
    // Older standalone repository users do not include the optional draft migration.
    let exists: i64 = connection.query_row(
        "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='finance_import_drafts'",
        [],
        |r| r.get(0),
    )?;
    if exists != 0 {
        active(connection)?;
    }
    Ok(())
}

/// None means the journal changed: retain the draft and show the new review.
pub fn confirm(connection: &Connection, draft: &Draft) -> Result<Option<usize>, Error> {
    let tx = connection.unchecked_transaction()?;
    if active(&tx)?.as_ref() != Some(draft) {
        return Err(Error::Invalid("import review changed"));
    }
    if repository::transactions(&tx)? != draft.journal
        || repository::rules(&tx)? != draft.baseline_rules
    {
        return Ok(None);
    }
    let rows = draft.review();
    let selected: Vec<_> = rows
        .iter()
        .enumerate()
        .filter(|(i, c)| draft.is_selected(*i, c))
        .collect();
    if selected.is_empty() {
        return Err(Error::Invalid("select at least one ready row"));
    }
    // Exact duplicates can never be forced in, even through a malformed selection.
    if rows.iter().enumerate().any(|(i, c)| {
        draft.selected.get(&i) == Some(&true)
            && !matches!(c.status, Status::New | Status::PossibleDuplicate)
    }) {
        return Err(Error::Invalid("selected row needs review"));
    }
    for (_, c) in &selected {
        repository::save_in_transaction(
            &tx,
            c.transaction
                .as_ref()
                .ok_or(Error::Invalid("missing import transaction"))?,
        )?;
    }
    repository::save_rules_in_transaction(&tx, &draft.rules)?;
    tx.execute(
        "DELETE FROM finance_import_drafts WHERE singleton=?1",
        params![1],
    )?;
    tx.commit()?;
    Ok(Some(selected.len()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        account::{AccountKind, defaults},
        statement::Provider,
    };
    const TEXT: &str = "支付宝交易记录明细\n交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号\n2026-07-02 19:30:00,餐饮美食,餐厅,晚餐,支出,68.00,银行卡,交易成功,trade-9,order-9\n2026-07-03 19:30:00,餐饮美食,超市,纸巾,支出,10.00,银行卡,交易成功,trade-10,order-10\n";
    fn db() -> Connection {
        navi_storage::memory(&[repository::SCHEMA, SCHEMA]).unwrap()
    }
    fn mapped(db: &Connection) -> Draft {
        let mut d = create(db, "a.csv", TEXT.as_bytes()).unwrap();
        d.rules.remember_method(
            Provider::Alipay,
            "银行卡",
            Account::parse("资产:银行").unwrap(),
        );
        save(db, &d).unwrap();
        d
    }
    #[test]
    fn draft_resume_commit_and_reimport_keep_identity() {
        let db = db();
        let d = mapped(&db);
        assert!(repository::transactions(&db).unwrap().is_empty());
        assert_eq!(repository::rules(&db).unwrap(), Rules::default());
        let resumed = active(&db).unwrap().unwrap();
        assert_eq!(resumed, d);
        assert_eq!(confirm(&db, &resumed).unwrap(), Some(2));
        assert!(active(&db).unwrap().is_none());
        assert_eq!(repository::transactions(&db).unwrap().len(), 2);
        let mut again = create(&db, "a.csv", TEXT.as_bytes()).unwrap();
        assert!(again.review().iter().all(|c| c.status == Status::Duplicate));
        again.selected.insert(0, true);
        save(&db, &again).unwrap();
        assert!(confirm(&db, &again).is_err());
        assert_eq!(repository::transactions(&db).unwrap().len(), 2);
    }
    #[test]
    fn journal_rules_and_draft_rollback_as_one_batch() {
        let db = db();
        let d = mapped(&db);
        db.execute_batch("CREATE TRIGGER fail_second BEFORE INSERT ON finance_transactions WHEN NEW.id='alipay:trade-10' BEGIN SELECT RAISE(ABORT,'disk failure'); END;").unwrap();
        assert!(confirm(&db, &d).is_err());
        assert!(repository::transactions(&db).unwrap().is_empty());
        assert_eq!(repository::rules(&db).unwrap(), Rules::default());
        assert_eq!(active(&db).unwrap(), Some(d));
        assert!(repository::accounts(&db).unwrap().is_empty());
    }
    #[test]
    fn concurrent_import_requires_fresh_review() {
        let db = db();
        let mut d = mapped(&db);
        let mut other = d.review()[0].transaction.clone().unwrap();
        other.id = "manual".into();
        other.source = Source::Manual;
        repository::save(&db, &other).unwrap();
        assert_eq!(confirm(&db, &d).unwrap(), None);
        assert_eq!(repository::transactions(&db).unwrap().len(), 1);
        d.selected.insert(0, true);
        d.refresh(&db).unwrap();
        save(&db, &d).unwrap();
        assert_eq!(d.review()[0].status, Status::PossibleDuplicate);
        assert!(!d.is_selected(0, &d.review()[0]));
        assert_eq!(confirm(&db, &d).unwrap(), Some(1));
        assert_eq!(repository::transactions(&db).unwrap().len(), 2);
    }
    #[test]
    fn explicit_refund_reverses_expense_and_repayment_needs_counteraccount() {
        let db = db();
        let text = "招商银行信用卡对账单 2026年07月\n交易明细\n07/02 07/03 商户退款 -68.00 1234 -68.00\n07/03 07/04 自动还款 -100.00 1234 -100.00\n07/04 07/05 不明贷记 -10.00 1234 -10.00\n";
        let mut d = create(&db, "card.txt", text.as_bytes()).unwrap();
        let card = Account::parse("负债:信用卡").unwrap();
        d.rules.remember_method(
            Provider::CmbCreditCard,
            "招商银行信用卡(1234)",
            card.clone(),
        );
        let rows = d.review();
        assert_eq!(rows.len(), 3);
        let refund = rows[0].transaction.as_ref().unwrap();
        assert_eq!(refund.amount_in(&defaults::other_expense()), -6800);
        assert_eq!(refund.amount_in(&card), 6800);
        assert_eq!(rows[1].status, Status::NeedsAttention);
        assert!(rows[1].transaction.is_none());
        assert_eq!(rows[2].status, Status::NeedsAttention);
        d.corrections.insert(
            1,
            Correction {
                kind: Kind::TransferIn,
                category: defaults::other_expense(),
                other: Some(Account::parse("资产:银行").unwrap()),
            },
        );
        let t = d.review()[1].transaction.clone().unwrap();
        assert_eq!(t.amount_in(&card), 10000);
        assert!(
            t.postings
                .iter()
                .all(|p| p.account.kind() != AccountKind::Income
                    && p.account.kind() != AccountKind::Expenses)
        );
    }
    #[test]
    fn refunded_purchase_and_refund_pair_require_explicit_review_before_netting_zero() {
        let db = db();
        let text = "支付宝交易记录明细\n交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号\n2026-07-02 19:30:00,餐饮美食,餐厅,晚餐,支出,68.00,余额,已退款,buy,order\n2026-07-03 19:30:00,退款,餐厅,晚餐退款,收入,68.00,余额,退款成功,refund,order\n";
        let mut d = create(&db, "pair.csv", text.as_bytes()).unwrap();
        let own = Account::parse("资产:支付宝").unwrap();
        d.rules
            .remember_method(Provider::Alipay, "余额", own.clone());
        let rows = d.review();
        assert_eq!(rows.len(), 2);
        assert!(rows.iter().all(|c| c.status == Status::NeedsAttention));
        assert!(!d.is_selected(0, &rows[0]) && !d.is_selected(1, &rows[1]));
        for (i, kind) in [(0, Kind::Expense), (1, Kind::Refund)] {
            d.corrections.insert(
                i,
                Correction {
                    kind,
                    category: defaults::expense("餐饮"),
                    other: None,
                },
            );
        }
        save(&db, &d).unwrap();
        assert_eq!(confirm(&db, &d).unwrap(), Some(2));
        let entries = repository::transactions(&db).unwrap();
        assert_eq!(journal::balances(&entries)[&own], 0);
        assert_eq!(journal::balances(&entries)[&defaults::expense("餐饮")], 0);
    }
    #[test]
    fn stale_refresh_preserves_concurrent_rules_and_local_pending_mapping() {
        let db = db();
        let mut d = mapped(&db);
        let mut concurrent = Rules::default();
        concurrent.remember_payee("Other payee", defaults::expense("购物"));
        repository::save_rules(&db, &concurrent).unwrap();
        assert_eq!(confirm(&db, &d).unwrap(), None);
        d.refresh(&db).unwrap();
        save(&db, &d).unwrap();
        assert_eq!(confirm(&db, &d).unwrap(), Some(2));
        let rules = repository::rules(&db).unwrap();
        assert_eq!(rules.payees, concurrent.payees);
        assert!(rules.methods["alipay"].contains_key("银行卡"));
    }
    #[test]
    fn pdf_and_empty_files_are_explicitly_rejected() {
        let db = db();
        assert!(create(&db, "a.pdf", b"%PDF-1.7").is_err());
        assert!(create(&db, "a.csv", b" ").is_err());
        assert!(active(&db).unwrap().is_none());
    }
}
