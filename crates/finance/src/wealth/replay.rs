use super::store::{checked, invalid};
use super::{OperationKind, WealthOperation};
use crate::{
    Result,
    builders::{EntryBuild, EntryDraft, PostingDraft},
    models::{Cost, EntryFlag},
    repos::{account_repository as accounts, journal_repository as journal},
};
use lifeos::sync::MutationStamper;
use rusqlite::Connection;
use rust_decimal::Decimal;

#[derive(Debug, Clone)]
struct Lot {
    quantity: Decimal,
    cost: Decimal,
}
#[derive(Default, Debug)]
pub(super) struct Position {
    lots: Vec<Lot>,
    pub quantity: Decimal,
    pub cost: Decimal,
    pub realized: Decimal,
    pub dividends: Decimal,
}
impl Position {
    fn consume(&mut self, quantity: Decimal) -> Result<Decimal> {
        if quantity > self.quantity {
            return Err(invalid("卖出数量超过当时可用持仓，不能保存此项修改"));
        }
        let mut remaining = quantity;
        let mut cost = Decimal::ZERO;
        for lot in &mut self.lots {
            if remaining == Decimal::ZERO {
                break;
            }
            let take = remaining.min(lot.quantity);
            if take == Decimal::ZERO {
                continue;
            }
            let part = if take == lot.quantity {
                lot.cost
            } else {
                checked(checked(lot.cost.checked_mul(take))?.checked_div(lot.quantity))?
            };
            lot.quantity = checked(lot.quantity.checked_sub(take))?;
            lot.cost = checked(lot.cost.checked_sub(part))?;
            remaining = checked(remaining.checked_sub(take))?;
            cost = checked(cost.checked_add(part))?;
        }
        self.quantity = checked(self.quantity.checked_sub(quantity))?;
        self.cost = checked(self.cost.checked_sub(cost))?;
        Ok(cost)
    }
}
fn leg(account: &str, units: Decimal, unit: &str, cost: Option<Cost>) -> PostingDraft {
    PostingDraft {
        position: 0,
        account_id: account.into(),
        units,
        unit: unit.into(),
        cost,
        price: None,
    }
}
fn annotation(per_unit: Decimal, currency: &str) -> Option<Cost> {
    Some(Cost {
        per_unit,
        currency: currency.into(),
        lot_id: None,
        acquired_on: None,
    })
}
fn neg(v: Decimal) -> Result<Decimal> {
    checked(Decimal::ZERO.checked_sub(v))
}
/// One deterministic FIFO replay powers write validation and read projections.
fn apply(
    position: &mut Position,
    op: &WealthOperation,
    opening: &str,
    gains: &str,
    dividend: &str,
    fees: &str,
) -> Result<EntryBuild> {
    let d = &op.details;
    let currency = &op.currency;
    let mut legs = Vec::new();
    let cash = d.cash_account_id.as_deref().unwrap_or(&d.account_id);
    match d.kind {
        OperationKind::Opening | OperationKind::Buy => {
            let gross = checked(d.quantity.checked_mul(d.unit_price))?;
            let cost = checked(gross.checked_add(d.fees))?;
            let per_unit = checked(cost.checked_div(d.quantity))?;
            position.quantity = checked(position.quantity.checked_add(d.quantity))?;
            position.cost = checked(position.cost.checked_add(cost))?;
            position.lots.push(Lot {
                quantity: d.quantity,
                cost,
            });
            legs.push(leg(
                &d.account_id,
                d.quantity,
                &d.asset_id,
                annotation(per_unit, currency),
            ));
            legs.push(leg(
                if d.kind == OperationKind::Opening {
                    opening
                } else {
                    cash
                },
                neg(cost)?,
                currency,
                None,
            ));
        }
        OperationKind::Sell => {
            let cost = position.consume(d.quantity)?;
            let gross = checked(d.quantity.checked_mul(d.unit_price))?;
            let gain = checked(gross.checked_sub(cost))?;
            position.realized = checked(
                position
                    .realized
                    .checked_add(checked(gain.checked_sub(d.fees))?),
            )?;
            legs.push(leg(
                &d.account_id,
                neg(d.quantity)?,
                &d.asset_id,
                annotation(checked(cost.checked_div(d.quantity))?, currency),
            ));
            legs.push(leg(
                cash,
                checked(gross.checked_sub(d.fees))?,
                currency,
                None,
            ));
            if gain != Decimal::ZERO {
                legs.push(leg(gains, neg(gain)?, currency, None));
            }
            if d.fees != Decimal::ZERO {
                legs.push(leg(fees, d.fees, currency, None));
            }
        }
        OperationKind::Dividend => {
            if position.lots.is_empty() {
                return Err(invalid("分红日期之前必须有该资产的持仓记录"));
            }
            position.dividends = checked(
                position
                    .dividends
                    .checked_add(checked(d.amount.checked_sub(d.fees))?),
            )?;
            legs.push(leg(
                cash,
                checked(d.amount.checked_sub(d.fees))?,
                currency,
                None,
            ));
            legs.push(leg(dividend, neg(d.amount)?, currency, None));
            if d.fees != Decimal::ZERO {
                legs.push(leg(fees, d.fees, currency, None));
            }
        }
        OperationKind::Split => {
            if position.quantity <= Decimal::ZERO {
                return Err(invalid("拆股日期必须存在该资产持仓"));
            }
            let before = position.quantity;
            // Preserve basis; splits only change quantities and per-share basis.
            let mut after = Decimal::ZERO;
            for lot in &mut position.lots {
                lot.quantity = checked(lot.quantity.checked_mul(d.quantity))?;
                after = checked(after.checked_add(lot.quantity))?;
            }
            position.quantity = after;
            legs.push(leg(
                &d.account_id,
                checked(after.checked_sub(before))?,
                &d.asset_id,
                annotation(Decimal::ZERO, currency),
            ));
            legs.push(leg(opening, Decimal::ZERO, currency, None));
        }
    }
    for (i, p) in legs.iter_mut().enumerate() {
        p.position = i;
    }
    Ok(EntryBuild {
        entry: EntryDraft {
            date: d.date,
            settled_on: None,
            narration: d
                .note
                .clone()
                .filter(|s| !s.trim().is_empty())
                .unwrap_or_else(|| d.kind.label().into()),
            payee: None,
            flag: EntryFlag::Confirmed,
            tag_ids: vec![format!("wealth:{}", op.id), format!("asset:{}", d.asset_id)],
        },
        postings: legs,
    })
}
pub(super) fn project(
    ops: &[WealthOperation],
    asset: &str,
    account: &str,
    as_of: i64,
) -> Result<Position> {
    let mut p = Position::default();
    let mut relevant: Vec<_> = ops
        .iter()
        .filter(|o| {
            o.details.asset_id == asset
                && o.details.account_id == account
                && o.details.date <= as_of
        })
        .collect();
    relevant.sort_by(|a, b| {
        (a.details.date, a.sequence, &a.id).cmp(&(b.details.date, b.sequence, &b.id))
    });
    for o in relevant {
        apply(&mut p, o, "", "", "", "")?;
    }
    Ok(p)
}
pub(super) fn rewrite(
    conn: &Connection,
    st: &MutationStamper,
    ops: &[WealthOperation],
    asset: &str,
    account: &str,
) -> Result<()> {
    let system = |path: &str| -> Result<String> {
        accounts::find_system_account(conn, &st.owner_user_id, path)?
            .map(|a| a.id)
            .ok_or_else(|| invalid(format!("系统账户不可用: {path}")))
    };
    let opening = system("equity:openingBalance")?;
    let gains = system("income:capitalGains")?;
    let dividends = system("income:dividend")?;
    let fees = system("expense:trading:fee")?;
    let base = crate::repos::settings_repository::base_currency(conn)?;
    let fx = |conn: &Connection, from: &str, to: &str, date: i64| {
        crate::fx::rate_at(conn, from, to, date)
    };
    let mut p = Position::default();
    let mut relevant: Vec<_> = ops
        .iter()
        .filter(|o| o.details.asset_id == asset && o.details.account_id == account)
        .collect();
    relevant.sort_by(|a, b| {
        (a.details.date, a.sequence, &a.id).cmp(&(b.details.date, b.sequence, &b.id))
    });
    for o in relevant {
        if let Some(old) = journal::get(conn, &o.id)?
            && old.entry.sync.owner_user_id != st.owner_user_id
        {
            return Err(invalid("分录不属于当前数据空间"));
        }
        let build = apply(&mut p, o, &opening, &gains, &dividends, &fees)?;
        journal::create_in_transaction(conn, st, &fx, &base, build, Some(&o.id))?;
    }
    Ok(())
}

/// Sync transports individual rows. Never report a complete financial value
/// while operation metadata and its journal legs describe different revisions.
pub(super) fn verify(conn: &Connection, owner: &str, ops: &[WealthOperation]) -> Result<()> {
    let journals = journal::list_owned(conn, owner, None, None)?;
    let pending = || invalid("投资记录尚未完整同步，请完成同步后重试");
    if journals.iter().any(|j| {
        j.entry.tag_ids.iter().any(|t| t.starts_with("wealth:"))
            && !ops.iter().any(|o| o.id == j.entry.id)
    }) {
        return Err(pending());
    }
    if ops.is_empty() {
        return Ok(());
    }
    let system = |path: &str| -> Result<String> {
        accounts::find_system_account(conn, owner, path)?
            .filter(|a| a.sync.owner_user_id == owner && a.sync.deleted_at.is_none())
            .map(|a| a.id)
            .ok_or_else(pending)
    };
    let opening = system("equity:openingBalance")?;
    let gains = system("income:capitalGains")?;
    let dividend = system("income:dividend")?;
    let fees = system("expense:trading:fee")?;
    let mut positions = std::collections::BTreeMap::<(String, String), Position>::new();
    let mut ordered: Vec<_> = ops.iter().collect();
    ordered.sort_by(|a, b| {
        (a.details.date, a.sequence, &a.id).cmp(&(b.details.date, b.sequence, &b.id))
    });
    for op in ordered {
        let p = positions
            .entry((op.details.asset_id.clone(), op.details.account_id.clone()))
            .or_default();
        let expected = apply(p, op, &opening, &gains, &dividend, &fees)?;
        let actual = journals
            .iter()
            .find(|j| j.entry.id == op.id)
            .ok_or_else(pending)?;
        if actual.entry.date != expected.entry.date
            || actual.entry.narration != expected.entry.narration
            || actual.postings.len() != expected.postings.len()
            || !expected
                .entry
                .tag_ids
                .iter()
                .all(|t| actual.entry.tag_ids.contains(t))
            || actual
                .postings
                .iter()
                .zip(&expected.postings)
                .any(|(a, b)| {
                    a.sync.owner_user_id != owner
                        || a.account_id != b.account_id
                        || a.units != b.units
                        || a.unit != b.unit
                        || a.cost != b.cost
                        || a.price != b.price
                })
        {
            return Err(pending());
        }
    }
    Ok(())
}
