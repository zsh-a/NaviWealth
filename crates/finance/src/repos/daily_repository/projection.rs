use super::*;
pub(super) fn project(
    conn: &Connection,
    owner: &str,
    row: journal::EntryWithPostings,
) -> Result<FinanceRecord> {
    if row
        .entry
        .tag_ids
        .iter()
        .any(|tag| tag.starts_with("wealth:"))
    {
        let op = crate::wealth::operation(conn, owner, &row.entry.id)?;
        let asset = crate::wealth::asset(conn, owner, &op.details.asset_id)?;
        let account = owned_account(conn, owner, &op.details.account_id, false)?;
        let cash = op
            .details
            .cash_account_id
            .as_deref()
            .map(|id| owned_account(conn, owner, id, false))
            .transpose()?;
        let amount = match op.details.kind {
            crate::wealth::OperationKind::Opening => op
                .details
                .quantity
                .checked_mul(op.details.unit_price)
                .ok_or_else(|| invalid("持仓成本超出支持范围"))?,
            _ => op.cash_amount,
        };
        return Ok(FinanceRecord {
            source: RecordSource::Wealth,
            investment_kind: Some(op.details.kind),
            editable: false,
            id: op.id,
            kind: RecordKind::Investment,
            date: op.details.date,
            amount,
            currency: op.currency,
            account_id: account.id,
            account_name: account.name,
            category_id: None,
            category_name: Some(op.details.kind.label().to_owned()),
            destination_account_id: cash.as_ref().map(|a| a.id.clone()),
            destination_account_name: cash.map(|a| a.name),
            destination_amount: None,
            destination_currency: None,
            payee: Some(asset.details.name),
            note: op.details.note,
        });
    }
    let source = if row
        .entry
        .tag_ids
        .iter()
        .any(|tag| tag.starts_with("recurring:") || tag.starts_with("liability:"))
    {
        RecordSource::Planning
    } else if row
        .entry
        .tag_ids
        .iter()
        .any(|tag| tag.starts_with("reconciliation:"))
    {
        RecordSource::Reconciliation
    } else {
        RecordSource::Daily
    };
    let mut record = project_ledger(conn, owner, row)?;
    if source != RecordSource::Daily {
        record.source = source;
        record.editable = false;
    }
    Ok(record)
}

pub(super) fn project_ledger(
    conn: &Connection,
    owner: &str,
    row: journal::EntryWithPostings,
) -> Result<FinanceRecord> {
    let legs = row
        .postings
        .iter()
        .map(|posting| {
            let account = accounts::get_required(conn, &posting.account_id)?;
            if account.sync.owner_user_id != owner || posting.sync.owner_user_id != owner {
                return Err(invalid("记录账户所属数据空间不一致"));
            }
            Ok((posting, account))
        })
        .collect::<Result<Vec<_>>>()?;
    if legs.len() == 2 {
        let standard = row.entry.flag != crate::models::EntryFlag::Padding
            && legs
                .iter()
                .all(|(p, a)| p.unit == a.currency || !custody(a))
            && legs.iter().all(|(p, _)| p.cost.is_none())
            && match (
                legs.iter().find(|(_, a)| a.side == AccountSide::Expense),
                legs.iter().find(|(_, a)| a.side == AccountSide::Income),
            ) {
                (Some((expense, _)), None) => {
                    expense.units > Decimal::ZERO
                        && legs.iter().any(|(p, a)| {
                            custody(a) && p.units < Decimal::ZERO && p.price.is_none()
                        })
                        && expense.price.is_none()
                }
                (None, Some((income, _))) => {
                    income.units < Decimal::ZERO
                        && legs.iter().any(|(p, a)| {
                            custody(a) && p.units > Decimal::ZERO && p.price.is_none()
                        })
                        && income.price.is_none()
                }
                (None, None) => {
                    let opening = legs.iter().any(|(_, a)| {
                        a.id == system_accounts::system_account_id(owner, "equity:openingBalance")
                    });
                    (opening
                        && legs.iter().any(|(_, a)| custody(a))
                        && legs.iter().all(|(p, _)| p.price.is_none()))
                        || (legs.iter().all(|(_, a)| custody(a))
                            && legs
                                .iter()
                                .any(|(p, _)| p.units < Decimal::ZERO && p.price.is_none())
                            && legs.iter().any(|(p, _)| p.units > Decimal::ZERO))
                }
                _ => false,
            };
        if standard {
            return project_daily(conn, owner, row);
        }
    }
    let expense: Vec<_> = legs
        .iter()
        .filter(|(_, a)| a.side == AccountSide::Expense)
        .collect();
    let income: Vec<_> = legs
        .iter()
        .filter(|(_, a)| a.side == AccountSide::Income)
        .collect();
    let infer = |items: Vec<&(&crate::models::Posting, Account)>,
                 kind: RecordKind|
     -> Result<Option<(RecordKind, String, Decimal)>> {
        let mut sum = Decimal::ZERO;
        let mut currency = None;
        for (posting, _) in items {
            let (unit, weight) = posting_weight(posting)?;
            if (kind == RecordKind::Expense && weight < Decimal::ZERO)
                || (kind == RecordKind::Income && weight > Decimal::ZERO)
            {
                return Ok(None);
            }
            if currency.as_ref().is_some_and(|current| current != &unit) {
                return Ok(None);
            }
            currency = Some(unit);
            sum = sum
                .checked_add(weight)
                .ok_or_else(|| invalid("分录合计超出支持范围"))?;
        }
        Ok(currency.map(|currency| {
            (
                kind,
                currency,
                if kind == RecordKind::Income {
                    -sum
                } else {
                    sum
                },
            )
        }))
    };
    let inferred = if !expense.is_empty() && income.is_empty() {
        infer(expense, RecordKind::Expense)?
    } else if expense.is_empty() && !income.is_empty() {
        infer(income, RecordKind::Income)?
    } else {
        None
    };
    let representative = legs
        .iter()
        .find(|(_, a)| custody(a))
        .or_else(|| legs.first());
    let (account_id, account_name) = if let Some((_, account)) = representative {
        let mut names = Vec::new();
        for (_, account) in legs.iter().filter(|(_, a)| custody(a)) {
            if !names.contains(&account.name) {
                names.push(account.name.clone());
            }
        }
        if names.is_empty() {
            names.push(account.name.clone());
        }
        (account.id.clone(), names.join(" / "))
    } else {
        (String::new(), "未关联账户".to_owned())
    };
    let (kind, currency, amount) = match inferred {
        Some(inferred) => inferred,
        None => {
            let (currency, amount) = representative
                .map(|(p, _)| posting_weight(p))
                .transpose()?
                .unwrap_or(("—".to_owned(), Decimal::ZERO));
            (RecordKind::Other, currency, amount)
        }
    };
    Ok(FinanceRecord {
        source: RecordSource::Other,
        investment_kind: None,
        editable: false,
        id: row.entry.id,
        kind,
        date: row.entry.date,
        amount,
        currency,
        account_id,
        account_name,
        category_id: None,
        category_name: Some(
            match kind {
                RecordKind::Expense => "多分录支出",
                RecordKind::Income => "多分录收入",
                _ => "其他记录 · 首项金额",
            }
            .to_owned(),
        ),
        destination_account_id: None,
        destination_account_name: None,
        destination_amount: None,
        destination_currency: None,
        payee: row.entry.payee,
        note: clean(Some(row.entry.narration)),
    })
}

pub(super) fn project_daily(
    conn: &Connection,
    owner: &str,
    row: journal::EntryWithPostings,
) -> Result<FinanceRecord> {
    if row.postings.len() != 2 {
        return Err(invalid("该记录不是可编辑的日常收支记录"));
    }
    let legs = row
        .postings
        .iter()
        .map(|p| {
            let a = accounts::get_required(conn, &p.account_id)?;
            if a.sync.owner_user_id != owner || p.sync.owner_user_id != owner {
                return Err(invalid("记录账户所属数据空间不一致"));
            }
            Ok((p, a))
        })
        .collect::<Result<Vec<_>>>()?;
    let category = legs
        .iter()
        .find(|(_, a)| matches!(a.side, AccountSide::Expense | AccountSide::Income));
    let opening = legs
        .iter()
        .any(|(_, a)| a.id == system_accounts::system_account_id(owner, "equity:openingBalance"));
    let kind = match category.map(|(_, a)| a.side) {
        Some(AccountSide::Expense) => RecordKind::Expense,
        Some(AccountSide::Income) => RecordKind::Income,
        _ if opening => RecordKind::OpeningBalance,
        _ => RecordKind::Transfer,
    };
    let (source, account) = if kind == RecordKind::Transfer {
        legs.iter()
            .find(|(p, a)| custody(a) && p.units < Decimal::ZERO)
    } else {
        legs.iter().find(|(_, a)| custody(a))
    }
    .ok_or_else(|| invalid("记录缺少资金账户"))?;
    let destination = if kind == RecordKind::Transfer {
        Some(
            legs.iter()
                .find(|(p, a)| custody(a) && p.units > Decimal::ZERO && a.id != account.id)
                .ok_or_else(|| invalid("转账记录缺少收款账户"))?,
        )
    } else {
        None
    };
    let note = clean(Some(row.entry.narration)).filter(|n| {
        !matches!(
            n.as_str(),
            "Expense" | "Income" | "Transfer" | "Opening Balance" | "Opening balance"
        )
    });
    Ok(FinanceRecord {
        source: RecordSource::Daily,
        investment_kind: None,
        editable: true,
        id: row.entry.id,
        kind,
        date: row.entry.date,
        amount: if kind == RecordKind::OpeningBalance {
            source.units
        } else {
            source.units.abs()
        },
        currency: source.unit.clone(),
        account_id: account.id.clone(),
        account_name: account.name.clone(),
        category_id: category.map(|(_, a)| a.id.clone()),
        category_name: category
            .map(|(_, a)| category_label(conn, owner, a))
            .transpose()?,
        destination_account_id: destination.map(|(_, a)| a.id.clone()),
        destination_account_name: destination.map(|(_, a)| a.name.clone()),
        destination_amount: destination.map(|(p, _)| p.units),
        destination_currency: destination.map(|(_, account)| account.currency.clone()),
        payee: row.entry.payee,
        note,
    })
}
