//! The complete allocation tree is one synced aggregate, so a remote merge
//! cannot combine independent edits into invalid sibling totals.
use super::*;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AssetTarget {
    pub asset_id: Option<String>,
    pub weight_bps: u32,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Sleeve {
    pub id: String,
    pub name: String,
    pub target_bps: u32,
    pub tolerance_bps: u32,
    pub targets: Vec<AssetTarget>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Portfolio {
    pub id: String,
    pub name: String,
    pub target_bps: u32,
    pub sleeves: Vec<Sleeve>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CapitalInclusion {
    pub portfolio_id: String,
    pub sleeve_id: String,
    pub account_id: String,
    pub asset_id: Option<String>,
    #[serde(with = "decimal")]
    pub quantity: Decimal,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InvestmentPlan {
    pub name: String,
    pub currency: String,
    pub portfolios: Vec<Portfolio>,
    pub inclusions: Vec<CapitalInclusion>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct AllocationMetric {
    pub portfolio_id: String,
    pub sleeve_id: Option<String>,
    pub asset_id: Option<String>,
    pub label: String,
    pub actual_value: Option<Decimal>,
    pub target_bps: u32,
    pub actual_bps: Option<Decimal>,
    pub drift_bps: Option<Decimal>,
    pub outside_tolerance: bool,
}
#[derive(Debug, Clone, PartialEq)]
pub struct RebalanceTask {
    pub portfolio_id: String,
    pub sleeve_id: String,
    pub asset_id: Option<String>,
    pub delta_value: Decimal,
    pub reason: String,
}
#[derive(Debug, Clone, PartialEq)]
pub struct PortfolioSnapshot {
    pub plan_id: String,
    pub as_of: i64,
    pub currency: String,
    pub total_value: Option<Decimal>,
    pub allocations: Vec<AllocationMetric>,
    pub tasks: Vec<RebalanceTask>,
    pub warnings: Vec<String>,
    pub missing_values: Vec<String>,
    pub transfers_pending: bool,
}
fn total_weights(mut weights: impl Iterator<Item = u32>) -> Result<()> {
    if weights.try_fold(0_u32, |sum, v| sum.checked_add(v)) != Some(10000) {
        return Err(invalid("同级配置权重合计必须为 100%"));
    }
    Ok(())
}
fn validate_structure(d: &InvestmentPlan) -> Result<()> {
    name(&d.name)?;
    currency(&d.currency)?;
    total_weights(d.portfolios.iter().map(|p| p.target_bps))?;
    let mut ids = std::collections::BTreeSet::new();
    for p in &d.portfolios {
        name(&p.name)?;
        if p.id.is_empty() || !ids.insert(p.id.clone()) {
            return Err(invalid("投资组合身份重复"));
        }
        total_weights(p.sleeves.iter().map(|s| s.target_bps))?;
        for s in &p.sleeves {
            name(&s.name)?;
            if s.id.is_empty() || !ids.insert(s.id.clone()) || s.tolerance_bps > 10000 {
                return Err(invalid("策略身份或容忍偏差无效"));
            }
            total_weights(s.targets.iter().map(|t| t.weight_bps))?;
            let mut targets = std::collections::BTreeSet::new();
            for t in &s.targets {
                if !targets.insert(t.asset_id.clone()) {
                    return Err(invalid("策略内目标不能重复"));
                }
            }
        }
    }
    for i in &d.inclusions {
        positive(i.quantity)?;
        if !d
            .portfolios
            .iter()
            .any(|p| p.id == i.portfolio_id && p.sleeves.iter().any(|s| s.id == i.sleeve_id))
        {
            return Err(invalid("纳入资产的组合或策略不存在"));
        }
    }
    Ok(())
}
/// All includes, across all saved plans, must fit actual open quantities.
pub fn save_portfolio_plan(
    conn: &mut Connection,
    st: &MutationStamper,
    id: Option<&str>,
    draft: InvestmentPlan,
    as_of: i64,
) -> Result<String> {
    validate_structure(&draft)?;
    if let Some(id) = id {
        let _: InvestmentPlan = get(conn, &st.owner_user_id, "portfolio", id)?;
    }
    let tx = conn.savepoint()?;
    for p in &draft.portfolios {
        for s in &p.sleeves {
            for target in &s.targets {
                if let Some(asset_id) = &target.asset_id {
                    let asset = crate::wealth::asset(&tx, &st.owner_user_id, asset_id)?;
                    if asset.archived {
                        return Err(invalid("配置目标资产已归档"));
                    }
                }
            }
        }
    }
    validate_available_capital(&tx, &st.owner_user_id, id, &draft, as_of)?;
    let id = id.map(str::to_owned).unwrap_or_else(lifeos::ids::new_id);
    put(&tx, st, "portfolio", &id, &draft)?;
    tx.commit()?;
    Ok(id)
}
fn validate_available_capital(
    conn: &Connection,
    owner: &str,
    id: Option<&str>,
    draft: &InvestmentPlan,
    as_of: i64,
) -> Result<()> {
    let prior = id
        .map(|id| get::<InvestmentPlan>(conn, owner, "portfolio", id))
        .transpose()?;
    let quantity_in =
        |items: &[CapitalInclusion], account: &str, asset: &Option<String>| -> Result<Decimal> {
            items
                .iter()
                .filter(|i| i.account_id == account && &i.asset_id == asset)
                .try_fold(Decimal::ZERO, |sum, i| add(sum, i.quantity))
        };
    let mut combined = list::<InvestmentPlan>(conn, owner, "portfolio")?
        .into_iter()
        .filter(|s| Some(s.id.as_str()) != id)
        .flat_map(|s| s.data.inclusions)
        .collect::<Vec<_>>();
    combined.extend(draft.inclusions.clone());
    let wealth = crate::wealth::snapshot(conn, owner, as_of, &draft.currency)?;
    let cash = crate::wealth::cash_balances(conn, owner, as_of)?;
    let mut included: BTreeMap<(String, Option<String>), Decimal> = BTreeMap::new();
    for i in &combined {
        let k = (i.account_id.clone(), i.asset_id.clone());
        let total = add(*included.get(&k).unwrap_or(&Decimal::ZERO), i.quantity)?;
        included.insert(k, total);
    }
    for ((account, asset), quantity) in included {
        let old_own = if let Some(prior) = &prior {
            quantity_in(&prior.inclusions, &account, &asset)?
        } else {
            Decimal::ZERO
        };
        let new_own = quantity_in(&draft.inclusions, &account, &asset)?;
        let available = if let Some(asset) = &asset {
            wealth
                .holdings
                .iter()
                .find(|h| h.account_id == account && &h.asset_id == asset)
                .map(|h| h.quantity)
        } else {
            cash.iter()
                .find(|c| c.account_id == account && !c.liability)
                .map(|c| c.amount)
        };
        // Existing conflicts stay explicitly unavailable while the user repairs
        // them. Reductions and unrelated edits must not require repairing every
        // other plan in one impossible cross-plan write.
        if available.is_none_or(|available| quantity > available) && new_own > old_own {
            return Err(invalid("纳入总量超过实际可用资产；资产不能重复分配"));
        }
    }
    Ok(())
}
pub fn portfolio_plans(conn: &Connection, owner: &str) -> Result<Vec<Stored<InvestmentPlan>>> {
    list(conn, owner, "portfolio")
}
fn inclusion_value(
    conn: &Connection,
    i: &CapitalInclusion,
    d: &InvestmentPlan,
    as_of: i64,
    wealth: &crate::wealth::WealthSnapshot,
    cash: &[crate::wealth::CashBalance],
) -> Result<Option<Decimal>> {
    if let Some(asset) = &i.asset_id {
        let Some(h) = wealth
            .holdings
            .iter()
            .find(|h| h.account_id == i.account_id && h.asset_id == *asset)
        else {
            return Ok(None);
        };
        if i.quantity > h.quantity || h.quantity <= Decimal::ZERO {
            return Ok(None);
        }
        h.base_value
            .map(|v| mul(div(v, h.quantity)?, i.quantity))
            .transpose()
    } else {
        let Some(c) = cash
            .iter()
            .find(|c| c.account_id == i.account_id && !c.liability)
        else {
            return Ok(None);
        };
        if i.quantity > c.amount {
            return Ok(None);
        }
        if c.currency == d.currency {
            Ok(Some(i.quantity))
        } else {
            crate::fx::rate_at(conn, &c.currency, &d.currency, as_of)
                .map(|rate| mul(i.quantity, rate))
                .transpose()
        }
    }
}
pub fn portfolio_snapshot(
    conn: &Connection,
    owner: &str,
    id: &str,
    as_of: i64,
) -> Result<PortfolioSnapshot> {
    let d: InvestmentPlan = get(conn, owner, "portfolio", id)?;
    validate_structure(&d)?;
    let wealth = crate::wealth::snapshot(conn, owner, as_of, &d.currency)?;
    let cash = crate::wealth::cash_balances(conn, owner, as_of)?;
    // A real trade or spending may reduce capacity after setup. Independent
    // sync aggregates may also each look valid in isolation. Read the complete
    // owner allocation before valuing any participating inclusion.
    let mut included: BTreeMap<(String, Option<String>), Decimal> = BTreeMap::new();
    for plan in list::<InvestmentPlan>(conn, owner, "portfolio")? {
        validate_structure(&plan.data)?;
        for i in plan.data.inclusions {
            let key = (i.account_id, i.asset_id);
            let value = add(*included.get(&key).unwrap_or(&Decimal::ZERO), i.quantity)?;
            included.insert(key, value);
        }
    }
    let mut conflicts = std::collections::BTreeSet::new();
    for ((account, asset), quantity) in included {
        let capacity = if let Some(asset) = &asset {
            wealth
                .holdings
                .iter()
                .find(|h| h.account_id == account && h.asset_id == *asset)
                .map(|h| h.quantity)
        } else {
            cash.iter()
                .find(|c| c.account_id == account && !c.liability)
                .map(|c| c.amount)
        };
        if capacity.is_none_or(|available| quantity > available) {
            conflicts.insert((account, asset));
        }
    }
    let mut values = Vec::new();
    let mut missing = Vec::new();
    let mut total = Decimal::ZERO;
    for i in &d.inclusions {
        let conflict = conflicts.contains(&(i.account_id.clone(), i.asset_id.clone()));
        let value = if conflict {
            None
        } else {
            inclusion_value(conn, i, &d, as_of, &wealth, &cash)?
        };
        if let Some(v) = value {
            total = add(total, v)?
        } else {
            let account = accounts::get(conn, &i.account_id)?
                .filter(|a| a.sync.owner_user_id == owner && a.sync.deleted_at.is_none())
                .map(|a| a.name)
                .unwrap_or_else(|| "资金账户不可用".into());
            let label = if let Some(asset) = &i.asset_id {
                crate::wealth::asset(conn, owner, asset)
                    .map(|a| a.details.name)
                    .unwrap_or_else(|_| "持仓不可用".into())
            } else {
                "现金".into()
            };
            missing.push(format!(
                "{account} / {label}：{}",
                if conflict {
                    "全部投资配置纳入合计超过真实可用量，或该资产已不存在；请调整纳入量"
                } else {
                    "缺少可用价格或汇率"
                }
            ));
        }
        values.push((i, value));
    }
    let complete = missing.is_empty();
    let total_value = complete.then_some(total);
    let mut allocations = Vec::new();
    let mut tasks = Vec::new();
    let mut warnings = Vec::new();
    let mut transfers_pending = false;
    if d.inclusions.is_empty() {
        warnings.push("尚未纳入资产；添加持仓或现金后才能比较配置和生成再平衡任务".to_owned());
    }
    for p in &d.portfolios {
        let pv = sum_values(
            values
                .iter()
                .filter(|(i, _)| i.portfolio_id == p.id)
                .map(|(_, v)| *v),
        )?;
        let pm = metric(
            &p.id,
            None,
            None,
            &p.name,
            pv,
            total_value,
            p.target_bps,
            500,
        )?;
        if pm.outside_tolerance {
            transfers_pending = true;
            warnings.push(format!("{} 的组合配置偏离目标；先调整纳入资产", p.name));
        }
        allocations.push(pm);
        for s in &p.sleeves {
            let sv = sum_values(
                values
                    .iter()
                    .filter(|(i, _)| i.sleeve_id == s.id)
                    .map(|(_, v)| *v),
            )?;
            let sm = metric(
                &p.id,
                Some(&s.id),
                None,
                &s.name,
                sv,
                pv,
                s.target_bps,
                s.tolerance_bps,
            )?;
            if sm.outside_tolerance {
                transfers_pending = true;
                warnings.push(format!("{} 的策略资金偏离目标；先调整纳入资产", s.name));
            }
            allocations.push(sm);
            let mut assets = s
                .targets
                .iter()
                .map(|t| t.asset_id.clone())
                .collect::<std::collections::BTreeSet<_>>();
            assets.extend(
                values
                    .iter()
                    .filter(|(i, _)| i.sleeve_id == s.id)
                    .map(|(i, _)| i.asset_id.clone()),
            );
            for asset in assets {
                let av = sum_values(
                    values
                        .iter()
                        .filter(|(i, _)| i.sleeve_id == s.id && i.asset_id == asset)
                        .map(|(_, v)| *v),
                )?;
                let target = s
                    .targets
                    .iter()
                    .find(|t| t.asset_id == asset)
                    .map_or(0, |t| t.weight_bps);
                let label = asset.clone().unwrap_or_else(|| "现金".to_owned());
                let am = metric(
                    &p.id,
                    Some(&s.id),
                    asset.as_deref(),
                    &label,
                    av,
                    sv,
                    target,
                    s.tolerance_bps,
                )?;
                if let (Some(value), Some(sleeve_value)) = (av, sv) {
                    let desired = div(
                        mul(sleeve_value, Decimal::from(target))?,
                        Decimal::from(10000),
                    )?;
                    let delta = sub(desired, value)?;
                    if am.outside_tolerance {
                        tasks.push(RebalanceTask {
                            portfolio_id: p.id.clone(),
                            sleeve_id: s.id.clone(),
                            asset_id: asset.clone(),
                            delta_value: delta,
                            reason: if delta > Decimal::ZERO {
                                "低于目标：手动买入或纳入资产"
                            } else {
                                "高于目标：手动卖出或转出纳入资产"
                            }
                            .to_owned(),
                        });
                    }
                }
                if am.actual_bps.is_some_and(|b| b > Decimal::from(4000)) {
                    warnings.push(format!("{label} 在 {} 中超过 40%，存在集中风险", s.name));
                }
                allocations.push(am);
            }
        }
    }
    if !complete {
        tasks.clear();
        warnings.push("估值或资产覆盖不足；补全后才能形成再平衡金额".to_owned());
    }
    if transfers_pending {
        tasks.clear();
    }
    Ok(PortfolioSnapshot {
        plan_id: id.to_owned(),
        as_of,
        currency: d.currency,
        total_value,
        allocations,
        tasks,
        warnings,
        missing_values: missing,
        transfers_pending,
    })
}
fn sum_values(values: impl Iterator<Item = Option<Decimal>>) -> Result<Option<Decimal>> {
    let mut sum = Decimal::ZERO;
    for v in values {
        let Some(v) = v else { return Ok(None) };
        sum = add(sum, v)?;
    }
    Ok(Some(sum))
}
#[allow(clippy::too_many_arguments)]
fn metric(
    portfolio: &str,
    sleeve: Option<&str>,
    asset: Option<&str>,
    label: &str,
    value: Option<Decimal>,
    denominator: Option<Decimal>,
    target: u32,
    tolerance: u32,
) -> Result<AllocationMetric> {
    let actual_bps = match (value, denominator) {
        (Some(v), Some(d)) if d > Decimal::ZERO => Some(div(mul(v, Decimal::from(10000))?, d)?),
        _ => None,
    };
    let drift = actual_bps
        .map(|a| sub(a, Decimal::from(target)))
        .transpose()?;
    Ok(AllocationMetric {
        portfolio_id: portfolio.to_owned(),
        sleeve_id: sleeve.map(str::to_owned),
        asset_id: asset.map(str::to_owned),
        label: label.to_owned(),
        actual_value: value,
        target_bps: target,
        actual_bps,
        drift_bps: drift,
        outside_tolerance: drift.is_some_and(|d| d.abs() > Decimal::from(tolerance)),
    })
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RebalanceReceipt {
    pub plan_id: String,
    pub operation_id: String,
    pub recorded_on: i64,
    pub before: InvestmentPlan,
    pub after: InvestmentPlan,
}
pub fn rebalance_receipts(
    conn: &Connection,
    owner: &str,
    plan_id: &str,
) -> Result<Vec<Stored<RebalanceReceipt>>> {
    let _: InvestmentPlan = get(conn, owner, "portfolio", plan_id)?;
    Ok(list::<RebalanceReceipt>(conn, owner, "rebalance_receipt")?
        .into_iter()
        .filter(|r| r.data.plan_id == plan_id)
        .collect())
}
/// A receipt proves a manually recorded buy/sell, and never executes an order.
pub fn link_rebalance_trade(
    conn: &mut Connection,
    st: &MutationStamper,
    plan_id: &str,
    operation_id: &str,
) -> Result<PortfolioSnapshot> {
    let tx = conn.savepoint()?;
    let mut plan: InvestmentPlan = get(&tx, &st.owner_user_id, "portfolio", plan_id)?;
    let before = plan.clone();
    let op = crate::wealth::operations(&tx, &st.owner_user_id, None)?
        .into_iter()
        .find(|o| o.id == operation_id)
        .ok_or_else(|| invalid("请选择真实成交记录"))?;
    if !matches!(
        op.details.kind,
        crate::wealth::OperationKind::Buy | crate::wealth::OperationKind::Sell
    ) {
        return Err(invalid("再平衡仅关联真实买卖记录"));
    }
    let rid = key(&[&st.owner_user_id, "rebalance", plan_id, operation_id]);
    if list::<RebalanceReceipt>(&tx, &st.owner_user_id, "rebalance_receipt")?
        .iter()
        .any(|r| r.id == rid)
    {
        return portfolio_snapshot(&tx, &st.owner_user_id, plan_id, lifeos::ids::now_secs());
    }
    if list::<RebalanceReceipt>(&tx, &st.owner_user_id, "rebalance_receipt")?
        .iter()
        .any(|r| r.data.operation_id == operation_id)
    {
        return Err(invalid("该成交已经用于其他投资计划的再平衡"));
    }
    if op.currency != plan.currency {
        return Err(invalid("请先手动调整跨币种纳入资产"));
    }
    let candidates = plan
        .portfolios
        .iter()
        .flat_map(|p| {
            p.sleeves
                .iter()
                .filter(|s| {
                    s.targets
                        .iter()
                        .any(|t| t.asset_id.as_deref() == Some(op.details.asset_id.as_str()))
                })
                .map(|s| (p.id.clone(), s.id.clone()))
        })
        .collect::<Vec<_>>();
    if candidates.len() != 1 {
        return Err(invalid(
            "存在多个资产策略，请先在投资配置中明确调整纳入资产",
        ));
    }
    let (pid, sid) = &candidates[0];
    let cash_id = op
        .details
        .cash_account_id
        .as_ref()
        .ok_or_else(|| invalid("成交记录缺少资金账户"))?;
    let holding_index = plan.inclusions.iter().position(|i| {
        i.sleeve_id == *sid
            && i.account_id == op.details.account_id
            && i.asset_id.as_deref() == Some(op.details.asset_id.as_str())
    });
    if op.details.kind == crate::wealth::OperationKind::Buy {
        if let Some(index) = holding_index {
            plan.inclusions[index].quantity =
                add(plan.inclusions[index].quantity, op.details.quantity)?;
        } else {
            plan.inclusions.push(CapitalInclusion {
                portfolio_id: pid.clone(),
                sleeve_id: sid.clone(),
                account_id: op.details.account_id.clone(),
                asset_id: Some(op.details.asset_id.clone()),
                quantity: op.details.quantity,
            });
        }
    } else {
        let index = holding_index.ok_or_else(|| invalid("卖出持仓未纳入该策略"))?;
        if plan.inclusions[index].quantity < op.details.quantity {
            return Err(invalid("卖出数量超过该策略纳入量"));
        }
        plan.inclusions[index].quantity =
            sub(plan.inclusions[index].quantity, op.details.quantity)?;
    }
    let cash_index = plan
        .inclusions
        .iter()
        .position(|i| i.sleeve_id == *sid && i.account_id == *cash_id && i.asset_id.is_none());
    if let Some(index) = cash_index {
        let quantity = add(plan.inclusions[index].quantity, op.cash_amount)?;
        if quantity < Decimal::ZERO {
            return Err(invalid("该策略纳入现金不足，请先明确资金归属"));
        }
        plan.inclusions[index].quantity = quantity;
    } else if op.cash_amount > Decimal::ZERO {
        plan.inclusions.push(CapitalInclusion {
            portfolio_id: pid.clone(),
            sleeve_id: sid.clone(),
            account_id: cash_id.clone(),
            asset_id: None,
            quantity: op.cash_amount,
        });
    } else {
        return Err(invalid("请先把成交使用的现金纳入该策略"));
    }
    plan.inclusions.retain(|i| i.quantity > Decimal::ZERO);
    validate_available_capital(
        &tx,
        &st.owner_user_id,
        Some(plan_id),
        &plan,
        lifeos::ids::now_secs(),
    )?;
    put(&tx, st, "portfolio", plan_id, &plan)?;
    put(
        &tx,
        st,
        "rebalance_receipt",
        &rid,
        &RebalanceReceipt {
            plan_id: plan_id.to_owned(),
            operation_id: operation_id.to_owned(),
            recorded_on: op.details.date,
            before,
            after: plan.clone(),
        },
    )?;
    let snapshot = portfolio_snapshot(&tx, &st.owner_user_id, plan_id, lifeos::ids::now_secs())?;
    tx.commit()?;
    Ok(snapshot)
}
/// Restore the allocation snapshot only while it has not changed since this
/// receipt. A later user configuration is never overwritten by undo.
pub fn unlink_rebalance_trade(
    conn: &mut Connection,
    st: &MutationStamper,
    plan_id: &str,
    operation_id: &str,
    restore_inclusions: bool,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let current: InvestmentPlan = get(&tx, &st.owner_user_id, "portfolio", plan_id)?;
    let rid = key(&[&st.owner_user_id, "rebalance", plan_id, operation_id]);
    let receipt: RebalanceReceipt = get(&tx, &st.owner_user_id, "rebalance_receipt", &rid)?;
    if restore_inclusions {
        if current != receipt.after {
            return Err(invalid(
                "投资配置已变更；请明确选择仅解除关联并保留当前配置",
            ));
        }
        put(&tx, st, "portfolio", plan_id, &receipt.before)?;
    }
    tombstone(&tx, st, "rebalance_receipt", &rid)?;
    tx.commit()?;
    Ok(())
}
