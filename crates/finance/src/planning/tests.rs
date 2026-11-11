use super::*;
use crate::{models::NewAccount, wealth};

fn d(s: &str) -> Decimal {
    Decimal::from_str_exact(s).unwrap()
}
fn date(s: &str) -> i64 {
    chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc()
        .timestamp()
}
fn fixture() -> (Connection, MutationStamper, String) {
    let c = Connection::open_in_memory().unwrap();
    for m in lifeos::db::migrations::core_migrations().steps() {
        c.execute_batch(m.sql).unwrap();
    }
    for m in [
        crate::tables::migration(),
        crate::tables::assets_migration(),
        wealth::migration(),
        migration(),
        crate::operations::migration(),
    ] {
        c.execute_batch(m.sql).unwrap();
    }
    let st = MutationStamper::new("u", "d");
    crate::system_accounts::seed_system_accounts(&c, &st).unwrap();
    let cash = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Bank, "银行", "CNY"),
    )
    .unwrap();
    let build = builders::opening_balance(
        date("2026-01-01"),
        &cash.id,
        accounts::system_account_id("u", "equity:openingBalance"),
        d("10000"),
        "CNY",
        None,
        None,
        vec![],
    )
    .unwrap();
    write_journal(&c, &st, "opening", "CNY", build).unwrap();
    (c, st, cash.id)
}
fn bill(cash: &str) -> Recurring {
    Recurring {
        name: "房租".into(),
        kind: FlowKind::Bill,
        account_id: cash.into(),
        category_id: accounts::system_account_id("u", "expense:housing"),
        currency: "CNY".into(),
        amount: d("1000"),
        first_due: date("2026-01-31"),
        interval_months: 1,
        end_due: None,
        paused: false,
    }
}
fn expense_category(c: &Connection) -> String {
    daily::categories(c, "u", daily::RecordKind::Expense).unwrap()[0]
        .0
        .clone()
}
fn outbox(c: &Connection) -> i64 {
    lifeos::sync::outbox::count(c).unwrap()
}
fn make_asset(c: &mut Connection, st: &MutationStamper) -> String {
    wealth::save_asset(
        c,
        st,
        None,
        wealth::AssetDraft {
            kind: "stock".into(),
            name: "示例股票".into(),
            market: Some("US".into()),
            symbol: Some("TEST".into()),
            currency: "CNY".into(),
            note: None,
        },
    )
    .unwrap()
    .id
}
#[allow(clippy::too_many_arguments)]
fn buy(
    c: &mut Connection,
    st: &MutationStamper,
    asset: &str,
    broker: &str,
    cash: &str,
    when: i64,
    q: Decimal,
    price: Decimal,
) -> wealth::WealthOperation {
    wealth::save_operation(
        c,
        st,
        None,
        wealth::OperationDraft {
            kind: wealth::OperationKind::Buy,
            asset_id: asset.into(),
            account_id: broker.into(),
            cash_account_id: Some(cash.into()),
            date: when,
            quantity: q,
            unit_price: price,
            fees: Decimal::ZERO,
            amount: Decimal::ZERO,
            note: None,
        },
    )
    .unwrap()
}
fn plan(cash: &str) -> InvestmentPlan {
    InvestmentPlan {
        name: "长期配置".into(),
        currency: "CNY".into(),
        portfolios: vec![Portfolio {
            id: "p".into(),
            name: "退休".into(),
            target_bps: 10000,
            sleeves: vec![Sleeve {
                id: "s".into(),
                name: "核心".into(),
                target_bps: 10000,
                tolerance_bps: 100,
                targets: vec![AssetTarget {
                    asset_id: None,
                    weight_bps: 10000,
                }],
            }],
        }],
        inclusions: vec![CapitalInclusion {
            portfolio_id: "p".into(),
            sleeve_id: "s".into(),
            account_id: cash.into(),
            asset_id: None,
            quantity: d("1000"),
        }],
    }
}

#[test]
fn budget_exact_categories_owner_and_transfer_exclusion() {
    let (mut c, st, cash) = fixture();
    let category = expense_category(&c);
    let id = save_budget(
        &mut c,
        &st,
        Budget {
            month: "2026-01".into(),
            category_id: category.clone(),
            currency: "CNY".into(),
            limit: d("200.00"),
        },
    )
    .unwrap();
    daily::save(
        &mut c,
        &st,
        None,
        &daily::RecordDraft {
            kind: daily::RecordKind::Expense,
            date: date("2026-01-15"),
            amount: d("13.37"),
            account_id: cash.clone(),
            category_id: Some(category),
            destination_account_id: None,
            destination_amount: None,
            payee: None,
            note: None,
        },
    )
    .unwrap();
    let dest = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Cash, "现金", "CNY"),
    )
    .unwrap();
    let b = builders::transfer(
        date("2026-01-20"),
        cash,
        dest.id,
        d("100"),
        "CNY",
        None,
        None,
        None,
        None,
        None,
        vec![],
    )
    .unwrap();
    write_journal(&c, &st, "transfer", "CNY", b).unwrap();
    let rows = budgets(&c, "u", "2026-01").unwrap();
    assert_eq!(rows[0].id, id);
    assert_eq!(rows[0].spent, d("13.37"));
    assert_eq!(rows[0].remaining, d("186.63"));
    assert_eq!(rows[0].entry_ids.len(), 1);
    assert!(budgets(&c, "other", "2026-01").unwrap().is_empty());
    assert!(
        save_budget(
            &mut c,
            &MutationStamper::new("other", "x"),
            rows[0].budget.clone()
        )
        .is_err()
    );
    assert!(month_bounds("2026-13").is_err());
}

#[test]
fn recurring_calendar_idempotency_skip_undo_and_atomic_failure() {
    let (mut c, st, cash) = fixture();
    let mut b = bill(&cash);
    b.category_id = expense_category(&c);
    let id = save_recurring(&mut c, &st, None, b).unwrap();
    let dates = occurrences(&c, "u", date("2026-01-01"), date("2026-04-01")).unwrap();
    assert_eq!(
        dates.iter().map(|o| o.due).collect::<Vec<_>>(),
        vec![date("2026-01-31"), date("2026-02-28"), date("2026-03-31")]
    );
    let first = resolve_occurrence(&mut c, &st, &id, dates[0].due, true)
        .unwrap()
        .unwrap();
    let count = outbox(&c);
    assert_eq!(
        resolve_occurrence(&mut c, &st, &id, dates[0].due, true).unwrap(),
        Some(first.clone())
    );
    assert_eq!(outbox(&c), count);
    assert_eq!(
        posting_sum(&c, "u", &cash, "CNY", date("2026-02-01")).unwrap(),
        d("9000")
    );
    undo_occurrence(&mut c, &st, &id, dates[0].due).unwrap();
    assert_eq!(
        posting_sum(&c, "u", &cash, "CNY", date("2026-02-01")).unwrap(),
        d("10000")
    );
    resolve_occurrence(&mut c, &st, &id, dates[1].due, false).unwrap();
    assert!(resolve_occurrence(&mut c, &st, &id, dates[1].due, true).is_err());
    let count = outbox(&c);
    c.execute_batch(r#"CREATE TRIGGER reject_resolution BEFORE INSERT ON "fin:planning" WHEN NEW.kind='resolution' BEGIN SELECT RAISE(ABORT,'failure'); END;"#).unwrap();
    assert!(resolve_occurrence(&mut c, &st, &id, dates[2].due, true).is_err());
    assert_eq!(outbox(&c), count);
    assert_eq!(
        posting_sum(&c, "u", &cash, "CNY", date("2026-04-01")).unwrap(),
        d("10000")
    );
    assert!(
        occurrences(&c, "other", date("2026-01-01"), date("2026-04-01"))
            .unwrap()
            .is_empty()
    );
}

#[test]
fn liability_exact_principal_interest_payment_duplicate_and_undo() {
    let (mut c, st, cash) = fixture();
    let id = create_liability(
        &mut c,
        &st,
        LiabilityDraft {
            name: "贷款".into(),
            currency: "CNY".into(),
            principal: d("1000"),
            annual_rate: d("0.12"),
            months: 3,
            opened_on: date("2026-01-01"),
            first_due: date("2026-02-01"),
        },
    )
    .unwrap();
    let schedule = liability_schedule(&c, "u", &id).unwrap();
    assert_eq!(
        schedule.iter().map(|i| i.principal).collect::<Vec<_>>(),
        vec![d("333.33"), d("333.34"), d("333.33")]
    );
    assert_eq!(schedule[0].interest, d("10"));
    assert!(pay_installment(&mut c, &st, &id, 1, &cash, date("2026-03-01")).is_err());
    let jid = pay_installment(&mut c, &st, &id, 0, &cash, date("2026-02-01")).unwrap();
    let count = outbox(&c);
    assert_eq!(
        pay_installment(&mut c, &st, &id, 0, &cash, date("2026-02-01")).unwrap(),
        jid
    );
    assert_eq!(outbox(&c), count);
    let debt = liabilities(&c, "u").unwrap()[0].data.account_id.clone();
    assert_eq!(
        posting_sum(&c, "u", &debt, "CNY", date("2026-02-02")).unwrap(),
        d("-666.67")
    );
    assert_eq!(
        posting_sum(&c, "u", &cash, "CNY", date("2026-02-02")).unwrap(),
        d("9656.67")
    );
    undo_installment(&mut c, &st, &id, 0).unwrap();
    assert_eq!(
        posting_sum(&c, "u", &debt, "CNY", date("2026-02-02")).unwrap(),
        d("-1000")
    );
    for i in 0..3 {
        pay_installment(&mut c, &st, &id, i, &cash, date("2026-05-01")).unwrap();
    }
    assert_eq!(
        posting_sum(&c, "u", &debt, "CNY", date("2026-06-01")).unwrap(),
        Decimal::ZERO
    );
    assert!(undo_installment(&mut c, &st, &id, 0).is_err());
    assert!(liability_schedule(&c, "other", &id).is_err());
}

#[test]
fn runway_distinguishes_assumptions_and_never_materializes() {
    let (mut c, st, cash) = fixture();
    let mut b = bill(&cash);
    b.category_id = expense_category(&c);
    let id = save_recurring(&mut c, &st, None, b.clone()).unwrap();
    let count = outbox(&c);
    let r = runway(&c, "u", date("2026-01-02"), "CNY", 90).unwrap();
    assert_eq!(r.starting_balance, d("10000"));
    assert_eq!(r.predicted_balance, d("7000"));
    assert_eq!(r.flows.len(), 3);
    assert_eq!(outbox(&c), count);
    assert!(!r.assumptions.is_empty());
    b.paused = true;
    save_recurring(&mut c, &st, Some(&id), b).unwrap();
    assert_eq!(
        runway(&c, "u", date("2026-01-02"), "CNY", 30)
            .unwrap()
            .predicted_balance,
        d("10000")
    );
    assert!(runway(&c, "u", 0, "CNY", 60).is_err());
}

#[test]
fn goals_link_real_transfer_then_track_deletion_and_owner() {
    let (mut c, st, cash) = fixture();
    let other = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Bank, "储蓄", "CNY"),
    )
    .unwrap();
    let build = builders::transfer(
        date("2026-02-01"),
        cash,
        other.id,
        d("200"),
        "CNY",
        None,
        None,
        None,
        None,
        None,
        vec![],
    )
    .unwrap();
    write_journal(&c, &st, "saving", "CNY", build).unwrap();
    let goal = Goal {
        name: "旅行".into(),
        currency: "CNY".into(),
        target: d("1000"),
        target_date: date("2026-12-01"),
        monthly_contribution: d("200"),
        asset_id: None,
    };
    let id = save_goal(&mut c, &st, None, goal.clone()).unwrap();
    contribute_goal(&mut c, &st, &id, "saving", d("200")).unwrap();
    assert_eq!(goals(&c, "u").unwrap()[0].remaining, d("800"));
    assert!(contribute_goal(&mut c, &st, &id, "saving", d("201")).is_err());
    let second = save_goal(&mut c, &st, None, goal).unwrap();
    assert!(contribute_goal(&mut c, &st, &second, "saving", d("100")).is_err());
    daily::delete_record(&mut c, &st, "saving").unwrap();
    assert_eq!(
        goals(&c, "u")
            .unwrap()
            .iter()
            .find(|g| g.id == id)
            .unwrap()
            .contributed,
        Decimal::ZERO
    );
    assert!(goals(&c, "other").unwrap().is_empty());
}

#[test]
fn fire_is_decimal_reproducible_and_no_model_or_history_required() {
    let plan = FirePlan {
        name: "退休".into(),
        currency: "CNY".into(),
        current_capital: d("1000"),
        monthly_expense: d("100"),
        monthly_income: d("400"),
        monthly_contribution: d("100"),
        annual_real_return: Decimal::ZERO,
        withdrawal_rate: d("0.1"),
        years: 10,
    };
    let r = calculate_fire(&plan).unwrap();
    assert_eq!(r.target_capital, d("12000"));
    assert_eq!(r.projected_capital, d("13000"));
    assert_eq!(r.months_to_target, Some(110));
    assert_eq!(r.savings_rate, Some(d("0.75")));
    assert_eq!(r, calculate_fire(&plan).unwrap());
    let mut bad = plan.clone();
    bad.annual_real_return = d("-1");
    assert!(calculate_fire(&bad).is_err());
    bad = plan;
    bad.current_capital = Decimal::MAX;
    bad.annual_real_return = d("1");
    assert!(calculate_fire(&bad).is_err());
}

#[test]
fn dca_saves_offline_then_only_matching_real_buy_completes_goal() {
    let (mut c, st, cash) = fixture();
    let asset = make_asset(&mut c, &st);
    let broker = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Broker, "证券", "CNY"),
    )
    .unwrap();
    let goal = save_goal(
        &mut c,
        &st,
        None,
        Goal {
            name: "长期投入".into(),
            currency: "CNY".into(),
            target: d("10000"),
            target_date: date("2030-01-01"),
            monthly_contribution: d("100"),
            asset_id: Some(asset.clone()),
        },
    )
    .unwrap();
    let id = save_dca(
        &mut c,
        &st,
        None,
        DcaPlan {
            name: "月定投".into(),
            currency: "CNY".into(),
            asset_id: asset.clone(),
            account_id: cash.clone(),
            amount: d("100"),
            first_due: date("2026-02-01"),
            interval_months: 1,
            months: 12,
            goal_id: Some(goal.clone()),
            paused: false,
        },
    )
    .unwrap();
    assert_eq!(
        dca_occurrences(&c, "u", date("2026-02-01"), date("2027-03-01"))
            .unwrap()
            .len(),
        12
    );
    let op = buy(
        &mut c,
        &st,
        &asset,
        &broker.id,
        &cash,
        date("2026-02-02"),
        d("10"),
        d("10"),
    );
    link_dca_trade(&mut c, &st, &id, date("2026-02-01"), &op.id).unwrap();
    let count = outbox(&c);
    link_dca_trade(&mut c, &st, &id, date("2026-02-01"), &op.id).unwrap();
    assert_eq!(outbox(&c), count);
    assert_eq!(goals(&c, "u").unwrap()[0].contributed, d("100"));
    assert!(link_dca_trade(&mut c, &st, &id, date("2026-03-01"), &op.id).is_err());
    assert!(wealth::delete_operation(&mut c, &st, &op.id).is_err());
    undo_dca_occurrence(&mut c, &st, &id, date("2026-02-01")).unwrap();
    assert_eq!(goals(&c, "u").unwrap()[0].contributed, Decimal::ZERO);
    assert!(wealth::operation(&c, "u", &op.id).is_ok());
    wealth::delete_operation(&mut c, &st, &op.id).unwrap();
}

#[test]
fn portfolio_exclusive_capital_totals_missing_price_and_manual_rebalance() {
    let (mut c, st, cash) = fixture();
    let mut p = plan(&cash);
    let id = save_portfolio_plan(&mut c, &st, None, p.clone(), date("2026-01-02")).unwrap();
    assert_eq!(
        portfolio_snapshot(&c, "u", &id, date("2026-01-02"))
            .unwrap()
            .total_value,
        Some(d("1000"))
    );
    p.inclusions[0].quantity = d("9500");
    assert!(save_portfolio_plan(&mut c, &st, None, p.clone(), date("2026-01-02")).is_err());
    p.portfolios[0].target_bps = 9999;
    assert!(save_portfolio_plan(&mut c, &st, Some(&id), p, date("2026-01-02")).is_err());
    let asset = make_asset(&mut c, &st);
    let broker = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Broker, "证券", "CNY"),
    )
    .unwrap();
    let mut p = plan(&cash);
    p.portfolios[0].sleeves[0].targets = vec![
        AssetTarget {
            asset_id: Some(asset.clone()),
            weight_bps: 5000,
        },
        AssetTarget {
            asset_id: None,
            weight_bps: 5000,
        },
    ];
    save_portfolio_plan(&mut c, &st, Some(&id), p, date("2026-01-02")).unwrap();
    assert_eq!(
        portfolio_snapshot(&c, "u", &id, date("2026-01-02"))
            .unwrap()
            .tasks
            .len(),
        2
    );
    let op = buy(
        &mut c,
        &st,
        &asset,
        &broker.id,
        &cash,
        date("2026-02-01"),
        d("50"),
        d("10"),
    );
    link_rebalance_trade(&mut c, &st, &id, &op.id).unwrap();
    let missing = portfolio_snapshot(&c, "u", &id, date("2026-02-02")).unwrap();
    assert!(missing.total_value.is_none());
    assert!(missing.tasks.is_empty());
    assert_eq!(missing.missing_values.len(), 1);
    wealth::record_price(
        &mut c,
        &st,
        &asset,
        d("10"),
        date("2026-02-01"),
        Some("manual".into()),
    )
    .unwrap();
    let complete = portfolio_snapshot(&c, "u", &id, date("2026-02-02")).unwrap();
    assert_eq!(complete.total_value, Some(d("1000")));
    assert!(complete.tasks.is_empty());
    let count = outbox(&c);
    link_rebalance_trade(&mut c, &st, &id, &op.id).unwrap();
    assert_eq!(outbox(&c), count);
    assert!(portfolio_snapshot(&c, "other", &id, date("2026-02-02")).is_err());
    assert!(wealth::delete_operation(&mut c, &st, &op.id).is_err());
    unlink_rebalance_trade(&mut c, &st, &id, &op.id, true).unwrap();
    assert_eq!(
        portfolio_plans(&c, "u").unwrap()[0].data.inclusions.len(),
        1
    );
    wealth::delete_operation(&mut c, &st, &op.id).unwrap();
}

#[test]
fn planning_aggregate_participates_in_logical_backup_and_restore() {
    let (mut c, st, cash) = fixture();
    let mut b = bill(&cash);
    b.category_id = expense_category(&c);
    let id = save_recurring(&mut c, &st, None, b).unwrap();
    let mut registry = crate::tables::sync_registry();
    register(&mut registry);
    wealth::register(&mut registry);
    let payload =
        lifeos::backup::export_payload(&registry, &c, None, "2026-01-01T00:00:00Z".into()).unwrap();
    assert!(
        payload
            .data
            .get(TABLE)
            .unwrap()
            .iter()
            .any(|r| r.get("id").and_then(|v| v.as_str()) == Some(&id))
    );
    let encoded = serde_json::to_string(&payload.data[TABLE][0]).unwrap();
    assert!(encoded.contains("payload"));
    c.execute(r#"DELETE FROM "fin:planning""#, []).unwrap();
    assert!(list_recurring(&c, "u").unwrap().is_empty());
    lifeos::backup::restore_payload(&registry, &mut c, &payload).unwrap();
    assert!(list_recurring(&c, "u").unwrap()[0].data.amount == d("1000"));
}

#[test]
fn source_identity_and_historical_action_evidence_survive_pause() {
    let (mut c, st, cash) = fixture();
    let mut draft = bill(&cash);
    draft.category_id = expense_category(&c);
    let id = save_recurring(&mut c, &st, None, draft.clone()).unwrap();
    let due = draft.first_due;
    let jid = resolve_occurrence(&mut c, &st, &id, due, true)
        .unwrap()
        .unwrap();
    assert_eq!(
        source_for_entry(&c, "u", &jid).unwrap(),
        Some(PlanningSource::Recurring {
            template_id: id.clone(),
            due
        })
    );
    assert_eq!(source_for_entry(&c, "other", &jid).unwrap(), None);
    draft.paused = true;
    save_recurring(&mut c, &st, Some(&id), draft.clone()).unwrap();
    let actions = planning_actions(&c, "u", date("2026-01-01"), date("2026-04-01")).unwrap();
    assert_eq!(actions.len(), 1);
    assert_eq!(actions[0].state, OccurrenceState::Posted);
    draft.amount = d("1200");
    assert!(save_recurring(&mut c, &st, Some(&id), draft.clone()).is_err());
    undo_occurrence(&mut c, &st, &id, due).unwrap();
    save_recurring(&mut c, &st, Some(&id), draft).unwrap();
}

#[test]
fn decimal_sync_wire_rejects_binary_numbers_and_invalid_money() {
    let budget = Budget {
        month: "2026-01".into(),
        category_id: "category".into(),
        currency: "CNY".into(),
        limit: d("0.1000000000000000000000000001"),
    };
    let mut json = serde_json::to_value(&budget).unwrap();
    assert_eq!(
        json["limit"].as_str(),
        Some("0.1000000000000000000000000001")
    );
    assert_eq!(
        serde_json::from_value::<Budget>(json.clone()).unwrap(),
        budget
    );
    json["limit"] = serde_json::json!(0.1);
    assert!(serde_json::from_value::<Budget>(json).is_err());
}

#[test]
fn saved_cash_scenario_is_explicit_and_keeps_authoritative_runway_unchanged() {
    let (mut c, st, _) = fixture();
    let base = runway(&c, "u", date("2026-01-02"), "CNY", 90).unwrap();
    let scenario = CashScenario {
        name: "休假".into(),
        currency: "CNY".into(),
        starts_on: date("2026-02-01"),
        one_off_change: d("-1000"),
        monthly_change: d("-500"),
        months: 2,
    };
    let id = save_cash_scenario(&mut c, &st, None, scenario.clone()).unwrap();
    let count = outbox(&c);
    let projected = simulate_runway(&base, &scenario).unwrap();
    assert_eq!(projected.predicted_balance, d("8000"));
    assert_eq!(base.predicted_balance, d("10000"));
    assert_eq!(outbox(&c), count);
    assert_eq!(
        runway(&c, "u", date("2026-01-02"), "CNY", 90).unwrap(),
        base
    );
    assert_eq!(cash_scenarios(&c, "u").unwrap()[0].id, id);
    assert!(cash_scenarios(&c, "other").unwrap().is_empty());
    let mut wrong = scenario;
    wrong.currency = "USD".into();
    assert!(simulate_runway(&base, &wrong).is_err());
}

#[test]
fn liability_partial_write_rolls_back_and_manual_repayment_prevents_overpay() {
    let (mut c, st, cash) = fixture();
    let id = create_liability(
        &mut c,
        &st,
        LiabilityDraft {
            name: "债务".into(),
            currency: "CNY".into(),
            principal: d("100"),
            annual_rate: d("0.12"),
            months: 1,
            opened_on: date("2026-01-01"),
            first_due: date("2026-02-01"),
        },
    )
    .unwrap();
    let count = outbox(&c);
    c.execute_batch(r#"CREATE TRIGGER reject_payment BEFORE INSERT ON "fin:planning" WHEN NEW.kind='resolution' BEGIN SELECT RAISE(ABORT,'failure'); END;"#).unwrap();
    assert!(pay_installment(&mut c, &st, &id, 0, &cash, date("2026-02-01")).is_err());
    assert_eq!(outbox(&c), count);
    assert_eq!(
        posting_sum(&c, "u", &cash, "CNY", date("2026-03-01")).unwrap(),
        d("10000")
    );
    c.execute_batch("DROP TRIGGER reject_payment").unwrap();
    let debt = liabilities(&c, "u").unwrap()[0].data.account_id.clone();
    let build = builders::transfer(
        date("2026-01-20"),
        &cash,
        &debt,
        d("1"),
        "CNY",
        None,
        None,
        None,
        None,
        None,
        vec![],
    )
    .unwrap();
    write_journal(&c, &st, "manual-repayment", "CNY", build).unwrap();
    assert!(pay_installment(&mut c, &st, &id, 0, &cash, date("2026-02-01")).is_err());
}

#[test]
fn unused_loan_correction_deletion_and_settled_archive_have_ledger_consequences() {
    let (mut c, st, cash) = fixture();
    let mut draft = LiabilityDraft {
        name: "待核对贷款".into(),
        currency: "CNY".into(),
        principal: d("100"),
        annual_rate: Decimal::ZERO,
        months: 1,
        opened_on: date("2026-01-01"),
        first_due: date("2026-02-01"),
    };
    let id = create_liability(&mut c, &st, draft.clone()).unwrap();
    let account = liabilities(&c, "u").unwrap()[0].data.account_id.clone();
    draft.principal = d("120");
    draft.name = "已核对贷款".into();
    update_liability(&mut c, &st, &id, draft.clone()).unwrap();
    assert_eq!(
        posting_sum(&c, "u", &account, "CNY", date("2026-03-01")).unwrap(),
        d("-120")
    );
    assert!(archive_liability(&mut c, &st, &id, true).is_err());
    pay_installment(&mut c, &st, &id, 0, &cash, date("2026-02-01")).unwrap();
    assert!(update_liability(&mut c, &st, &id, draft.clone()).is_err());
    assert!(delete_liability(&mut c, &st, &id).is_err());
    archive_liability(&mut c, &st, &id, true).unwrap();
    assert!(liabilities(&c, "u").unwrap()[0].data.archived);
    undo_installment(&mut c, &st, &id, 0).unwrap();
    assert!(!liabilities(&c, "u").unwrap()[0].data.archived);
    delete_liability(&mut c, &st, &id).unwrap();
    assert!(liabilities(&c, "u").unwrap().is_empty());
    assert!(
        accounts::get_required(&c, &account)
            .unwrap()
            .sync
            .deleted_at
            .is_some()
    );
}

#[test]
fn runway_carries_today_and_overdue_outflows_without_assuming_late_income() {
    let (mut c, st, cash) = fixture();
    let category = expense_category(&c);
    let as_of = date("2026-02-02") + 12 * 3600;
    for (name, due, amount) in [
        ("今天账单", date("2026-02-02"), d("100")),
        ("逾期账单", date("2026-02-01"), d("200")),
    ] {
        let mut draft = bill(&cash);
        draft.name = name.into();
        draft.category_id = category.clone();
        draft.amount = amount;
        draft.first_due = due;
        draft.end_due = Some(due);
        save_recurring(&mut c, &st, None, draft).unwrap();
    }
    let mut salary = bill(&cash);
    salary.kind = FlowKind::Income;
    salary.category_id = daily::categories(&c, "u", daily::RecordKind::Income).unwrap()[0]
        .0
        .clone();
    salary.name = "未确认工资".into();
    salary.amount = d("1000");
    salary.first_due = date("2026-02-01");
    salary.end_due = Some(salary.first_due);
    save_recurring(&mut c, &st, None, salary).unwrap();
    create_liability(
        &mut c,
        &st,
        LiabilityDraft {
            name: "本月还款".into(),
            currency: "CNY".into(),
            principal: d("50"),
            annual_rate: Decimal::ZERO,
            months: 1,
            opened_on: date("2026-01-01"),
            first_due: date("2026-02-01"),
        },
    )
    .unwrap();
    let asset = make_asset(&mut c, &st);
    save_dca(
        &mut c,
        &st,
        None,
        DcaPlan {
            name: "今天定投".into(),
            currency: "CNY".into(),
            asset_id: asset,
            account_id: cash.clone(),
            amount: d("25"),
            first_due: date("2026-02-02"),
            interval_months: 1,
            months: 1,
            goal_id: None,
            paused: false,
        },
    )
    .unwrap();
    let before = outbox(&c);
    let r = runway(&c, "u", as_of, "CNY", 30).unwrap();
    assert_eq!(r.starting_balance, d("10000"));
    assert_eq!(r.predicted_balance, d("9625"));
    assert_eq!(r.flows.len(), 4);
    assert!(
        r.flows
            .iter()
            .all(|f| f.due == as_of && f.amount < Decimal::ZERO && f.name.contains("原到期"))
    );
    assert!(
        r.assumptions
            .iter()
            .any(|a| a.contains("未确认工资") && a.contains("未计入可用余额"))
    );
    assert_eq!(outbox(&c), before);
    assert_eq!(
        posting_sum(&c, "u", &cash, "CNY", as_of).unwrap(),
        d("10000")
    );
}

#[test]
fn portfolio_read_rejects_total_inclusions_after_normal_sell_and_spend() {
    let (mut c, st, cash) = fixture();
    let asset = make_asset(&mut c, &st);
    let broker = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Broker, "证券", "CNY"),
    )
    .unwrap();
    buy(
        &mut c,
        &st,
        &asset,
        &broker.id,
        &cash,
        date("2026-01-02"),
        d("10"),
        d("100"),
    );
    wealth::record_price(&mut c, &st, &asset, d("100"), date("2026-01-02"), None).unwrap();
    let mut stock_plan = plan(&cash);
    stock_plan.inclusions = vec![
        CapitalInclusion {
            portfolio_id: "p".into(),
            sleeve_id: "s".into(),
            account_id: broker.id.clone(),
            asset_id: Some(asset.clone()),
            quantity: d("5")
        };
        2
    ];
    let stock_id = save_portfolio_plan(&mut c, &st, None, stock_plan, date("2026-01-03")).unwrap();
    assert_eq!(
        portfolio_snapshot(&c, "u", &stock_id, date("2026-01-03"))
            .unwrap()
            .total_value,
        Some(d("1000"))
    );
    wealth::save_operation(
        &mut c,
        &st,
        None,
        wealth::OperationDraft {
            kind: wealth::OperationKind::Sell,
            asset_id: asset,
            account_id: broker.id,
            cash_account_id: Some(cash.clone()),
            date: date("2026-01-04"),
            quantity: d("4"),
            unit_price: d("100"),
            fees: Decimal::ZERO,
            amount: Decimal::ZERO,
            note: None,
        },
    )
    .unwrap();
    let count = outbox(&c);
    let stale = portfolio_snapshot(&c, "u", &stock_id, date("2026-01-05")).unwrap();
    assert!(stale.total_value.is_none());
    assert!(stale.tasks.is_empty());
    assert!(
        stale
            .missing_values
            .iter()
            .any(|m| m.contains("纳入合计超过"))
    );
    assert_eq!(outbox(&c), count);
    let mut cash_plan = plan(&cash);
    cash_plan.inclusions[0].quantity = d("500");
    cash_plan.inclusions.push(cash_plan.inclusions[0].clone());
    let cash_id = save_portfolio_plan(&mut c, &st, None, cash_plan, date("2026-01-05")).unwrap();
    let expense = builders::expense(
        date("2026-01-06"),
        expense_category(&c),
        &cash,
        d("8800"),
        "CNY",
        None,
        None,
        None,
        vec![],
    )
    .unwrap();
    write_journal(&c, &st, "normal-spending", "CNY", expense).unwrap();
    assert_eq!(
        posting_sum(&c, "u", &cash, "CNY", date("2026-01-07")).unwrap(),
        d("600")
    );
    let stale = portfolio_snapshot(&c, "u", &cash_id, date("2026-01-07")).unwrap();
    assert!(stale.total_value.is_none());
    assert!(stale.tasks.is_empty());
}

#[test]
fn independently_synced_plans_cannot_double_value_the_same_cash() {
    let (mut c, st, cash) = fixture();
    let mut a = plan(&cash);
    a.inclusions[0].quantity = d("6000");
    let id = save_portfolio_plan(&mut c, &st, None, a.clone(), date("2026-01-02")).unwrap();
    // Simulate an independently valid remote aggregate arriving after local setup.
    put(&c, &st, "portfolio", "remote-plan", &a).unwrap();
    let before = outbox(&c);
    for plan_id in [&id, "remote-plan"] {
        let snapshot = portfolio_snapshot(&c, "u", plan_id, date("2026-01-02")).unwrap();
        assert!(snapshot.total_value.is_none());
        assert!(snapshot.tasks.is_empty());
        assert!(
            snapshot
                .allocations
                .iter()
                .all(|a| a.actual_value.is_none())
        );
    }
    assert_eq!(outbox(&c), before);
}
