use super::*;

pub(super) fn record_row(
    record: ReadSignal<FinanceRecord>,
    selected: Signal<Option<FinanceRecord>>,
    currencies: Signal<ui::RecordCurrencies>,
) -> impl IntoElement {
    dynamic(move || record_row_content(record.get(), selected, &currencies.get()))
}
pub(super) fn record_row_content(
    item: FinanceRecord,
    selected: Signal<Option<FinanceRecord>>,
    currencies: &ui::RecordCurrencies,
) -> AnyElement {
    let pressed = item.clone();
    let id = format!("record-{}", item.id);
    let title = record_title(&item);
    let detail = record_accounts(&item);
    let signed = record_value(&item);
    ui::transaction_row(
        title,
        detail,
        item.category_name.as_deref().unwrap_or(item.kind.label()),
        signed,
        currencies.row(item.currency.clone(), &item.account_id),
        id,
        move || {
            if pressed.source != RecordSource::Daily && pressed.source != RecordSource::Other {
                fui::navigate(format!("/activity/entry/{}", pressed.id));
            } else {
                selected.set(Some(pressed.clone()));
            }
        },
    )
    .child(fui::record_highlight(&item.id))
    .into_element()
}

pub(super) fn record_title(record: &FinanceRecord) -> String {
    let identity = record
        .payee
        .clone()
        .or(record.category_name.clone())
        .unwrap_or_else(|| record.kind.label().to_owned());
    match record.investment_kind {
        Some(kind) => format!("{} · {identity}", kind.label()),
        None => identity,
    }
}
pub(super) fn record_accounts(record: &FinanceRecord) -> String {
    match (record.kind, record.destination_account_name.as_deref()) {
        (RecordKind::Investment, Some(cash)) => {
            format!("结算 {cash} · 持仓 {}", record.account_name)
        }
        (RecordKind::Investment, None) => format!("持仓 {}", record.account_name),
        (RecordKind::Transfer, Some(destination)) => {
            format!("{} → {destination}", record.account_name)
        }
        _ => record.account_name.clone(),
    }
}
pub(super) fn record_value(record: &FinanceRecord) -> String {
    match (record.kind, record.investment_kind) {
        (_, Some(OperationKind::Opening)) => {
            format!("成本 {}", ui::money_for(record.amount, &record.currency))
        }
        (_, Some(OperationKind::Split)) => {
            format!("现金 {}", ui::money_for(record.amount, &record.currency))
        }
        (RecordKind::Expense, _) => {
            ui::format_money(record.amount, &record.currency, ui::MoneySign::Outflow)
        }
        (RecordKind::Income, _) => {
            ui::format_money(record.amount, &record.currency, ui::MoneySign::Inflow)
        }
        (RecordKind::Investment, _) if record.amount > Decimal::ZERO => {
            ui::format_money(record.amount, &record.currency, ui::MoneySign::Inflow)
        }
        _ => ui::money_for(record.amount, &record.currency),
    }
}
