use super::*;
pub fn records(
    conn: &Connection,
    owner: &str,
    filter: &RecordFilter,
    limit: i64,
    offset: i64,
) -> Result<Vec<FinanceRecord>> {
    if let (Some(from), Some(until)) = (filter.from, filter.until)
        && from >= until
    {
        return Err(invalid("开始日期必须早于结束日期"));
    }
    let query = filter.query.trim().to_lowercase();
    let mut rows = Vec::new();
    let mut skipped = 0_i64;
    for row in journal::list_owned_in_category(
        conn,
        owner,
        filter.from,
        filter.until,
        filter.category_id.as_deref(),
    )? {
        if filter
            .account_id
            .as_ref()
            .is_some_and(|id| !row.postings.iter().any(|posting| &posting.account_id == id))
        {
            continue;
        }
        let record = project(conn, owner, row)?;
        if filter.kind.is_some_and(|k| k != record.kind) {
            continue;
        }
        if !query.is_empty() {
            let haystack = format!(
                "{} {} {} {} {}",
                record.account_name,
                record
                    .destination_account_name
                    .as_deref()
                    .unwrap_or_default(),
                record.category_name.as_deref().unwrap_or_default(),
                record.payee.as_deref().unwrap_or_default(),
                record.note.as_deref().unwrap_or_default()
            )
            .to_lowercase();
            if !haystack.contains(&query) {
                continue;
            }
        }
        if skipped < offset.max(0) {
            skipped += 1;
            continue;
        }
        rows.push(record);
        if rows.len() >= limit.clamp(1, 200) as usize {
            break;
        }
    }
    Ok(rows)
}

pub fn monthly_totals(
    conn: &Connection,
    owner: &str,
    from: i64,
    until: i64,
) -> Result<Vec<(String, Decimal, Decimal)>> {
    if from >= until {
        return Err(invalid("开始日期必须早于结束日期"));
    }
    let mut totals: BTreeMap<String, (Decimal, Decimal)> = BTreeMap::new();
    for row in journal::list_owned(conn, owner, Some(from), Some(until))? {
        for posting in &row.postings {
            let account = accounts::get_required(conn, &posting.account_id)?;
            if posting.sync.owner_user_id != owner || account.sync.owner_user_id != owner {
                return Err(invalid("记录账户所属数据空间不一致"));
            }
            if !matches!(account.side, AccountSide::Expense | AccountSide::Income) {
                continue;
            }
            let (currency, weight) = posting_weight(posting)?;
            let pair = totals.entry(currency).or_default();
            if account.side == AccountSide::Expense {
                pair.1 = pair
                    .1
                    .checked_add(weight)
                    .ok_or_else(|| invalid("支出合计超出支持范围"))?;
            } else {
                pair.0 = pair
                    .0
                    .checked_sub(weight)
                    .ok_or_else(|| invalid("收入合计超出支持范围"))?;
            }
        }
    }

    Ok(totals
        .into_iter()
        .map(|(currency, (income, expense))| (currency, income, expense))
        .collect())
}

/// Stable category identities for query shortcuts, including renamed builtins
/// and user categories. Names are labels only.
#[derive(Debug, Clone, PartialEq)]
pub struct ExpenseCategory {
    pub id: String,
    pub name: String,
    pub system_key: Option<String>,
}
pub fn expense_categories(conn: &Connection, owner: &str) -> Result<Vec<ExpenseCategory>> {
    let mut q = conn.prepare_cached(r#"SELECT c.ledger_account_id, COALESCE(c.name_override,c.name), c.system_key
        FROM "fin:categories" c JOIN "fin:accounts" a ON a.id=c.ledger_account_id
        WHERE c.owner_user_id=?1 AND a.owner_user_id=?1 AND c.deleted_at IS NULL AND c.archived=0
        AND a.deleted_at IS NULL AND a.archived=0 AND a.category='expense'
        AND NOT EXISTS(SELECT 1 FROM "fin:categories" child WHERE child.parent_id=c.id AND child.owner_user_id=?1 AND child.deleted_at IS NULL)
        ORDER BY c.sort_order,c.name,c.id"#)?;
    Ok(q.query_map(params![owner], |r| {
        Ok(ExpenseCategory {
            id: r.get(0)?,
            name: r.get(1)?,
            system_key: r.get(2)?,
        })
    })?
    .collect::<std::result::Result<Vec<_>, _>>()?)
}
#[derive(Debug, Clone, PartialEq)]
pub struct DailySpending {
    pub date: i64,
    pub currency: String,
    pub amount: Decimal,
}
/// One read pass using the same exact expense-leg weights as monthly_totals.
/// No SQL float SUM, client pagination, income, transfer or opening balances.
pub fn daily_spending(
    conn: &Connection,
    owner: &str,
    from: i64,
    until: i64,
) -> Result<Vec<DailySpending>> {
    if from >= until {
        return Err(invalid("开始日期必须早于结束日期"));
    }
    let mut sums = BTreeMap::<(i64, String), Decimal>::new();
    for row in journal::list_owned(conn, owner, Some(from), Some(until))? {
        for posting in &row.postings {
            let account = accounts::get_required(conn, &posting.account_id)?;
            if posting.sync.owner_user_id != owner || account.sync.owner_user_id != owner {
                return Err(invalid("记录账户所属数据空间不一致"));
            }
            if account.side != AccountSide::Expense {
                continue;
            }
            let (currency, weight) = posting_weight(posting)?;
            let total = sums
                .entry((row.entry.date.div_euclid(86400) * 86400, currency))
                .or_default();
            *total = total
                .checked_add(weight)
                .ok_or_else(|| invalid("支出合计超出支持范围"))?;
        }
    }
    Ok(sums
        .into_iter()
        .map(|((date, currency), amount)| DailySpending {
            date,
            currency,
            amount,
        })
        .collect())
}

pub fn record(conn: &Connection, owner: &str, id: &str) -> Result<FinanceRecord> {
    project(conn, owner, owned_entry(conn, owner, id)?)
}
pub(super) fn posting_weight(posting: &crate::models::Posting) -> Result<(String, Decimal)> {
    if let Some(cost) = &posting.cost {
        return Ok((
            cost.currency.clone(),
            posting
                .units
                .checked_mul(cost.per_unit)
                .ok_or_else(|| invalid("分录金额超出支持范围"))?,
        ));
    }
    if let Some(price) = &posting.price {
        return Ok((
            price.currency.clone(),
            posting
                .units
                .checked_mul(price.per_unit)
                .ok_or_else(|| invalid("分录金额超出支持范围"))?,
        ));
    }
    Ok((posting.unit.clone(), posting.units))
}
