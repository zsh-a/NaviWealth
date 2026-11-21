//! Ledger rows and labels shared by Today, Records, Review, Assets and
//! capture: category names, transaction titles and the transaction row.

use navi_finance::{
    account::{Account, AccountKind},
    currency::Currency,
    journal::{Source, Transaction},
};
use nsh_core::prelude::*;

use super::form::*;
use crate::{
    data::{clock, finance},
    i18n::s,
    ui::{Type, Typo, color, surface::row_button},
};

pub(super) fn account_label(account: &Account) -> String {
    let kind = match account.kind() {
        AccountKind::Assets => s().asset_account,
        AccountKind::Liabilities => s().liability_account,
        _ => return category_label(account),
    };
    format!("{} · {kind}", crate::ui::currency::account_label(account))
}

pub(crate) fn category_label(account: &Account) -> String {
    if s().lang == crate::domain::recognition::Lang::Zh {
        return account.name().to_owned();
    }
    match account.name() {
        "餐饮" => "Dining",
        "买菜日用" => "Groceries",
        "交通" => "Transport",
        "居住" => "Housing",
        "购物" => "Shopping",
        "娱乐" => "Entertainment",
        "医疗" => "Health",
        "人情" => "Gifts",
        "其他" => "Other",
        "工资" => "Salary",
        other => other,
    }
    .to_owned()
}

pub(crate) fn transaction_title(t: &Transaction) -> String {
    if let Source::Investment { trade_id } = &t.source {
        let label = finance::holdings()
            .trades
            .iter()
            .find(|t| t.id == *trade_id)
            .map(|t| crate::pages::holdings::kind_label(t.kind))
            .unwrap_or(s().record_trade);
        return format!("{label} · {}", t.payee);
    }
    let parsed = parts(t);
    if t.payee.trim().is_empty() {
        parsed
            .as_ref()
            .map(|p| {
                if p.0 == Kind::Transfer {
                    s().transfer.to_owned()
                } else {
                    category_label(&p.2)
                }
            })
            .unwrap_or_else(|| {
                crate::pages::assets::balance_title(t)
                    .unwrap_or(s().transactions)
                    .to_owned()
            })
    } else {
        t.payee.clone()
    }
}

/// A ledger row for Today and Records. Transfers explicitly say Transfer and
/// never acquire a spending sign merely because money leaves one own account.
pub fn transaction_row(
    t: Transaction,
    leading: f32,
    on_press: impl Fn() + 'static,
) -> impl IntoElement {
    let investment = matches!(t.source, Source::Investment { .. });
    let system_record = crate::pages::assets::balance_title(&t).is_some();
    let investment_cash = match &t.source {
        Source::Investment { trade_id } => finance::holdings_snapshot()
            .trades
            .iter()
            .find(|trade| trade.id == *trade_id)
            .and_then(|trade| trade.cash.clone()),
        _ => None,
    };
    let parsed = if investment { None } else { parts(&t) };
    let amount = parsed
        .as_ref()
        .map(|p| {
            format!(
                "{}{}",
                match p.0 {
                    Kind::Expense => "−",
                    Kind::Income => "+",
                    Kind::Transfer => "",
                },
                crate::ui::currency::grouped(p.3)
            )
        })
        .unwrap_or_else(|| {
            if let Some(cash) = &investment_cash {
                return crate::ui::currency::grouped(
                    t.postings
                        .iter()
                        .find(|p| p.account == *cash)
                        .map_or(0, |p| p.amount),
                );
            }
            t.own_postings()
                .next()
                .map(|p| crate::ui::currency::grouped(p.amount))
                .unwrap_or_else(|| "—".into())
        });
    let kind = parsed.as_ref().map_or_else(
        || crate::pages::assets::balance_title(&t).unwrap_or(s().transactions),
        |p| p.0.label(s()),
    );
    let accounts = parsed
        .as_ref()
        .map(|p| {
            if p.0 == Kind::Transfer {
                format!(
                    "{} → {}",
                    crate::ui::currency::account_label(&p.1),
                    crate::ui::currency::account_label(&p.2)
                )
            } else {
                p.1.name().to_owned()
            }
        })
        .unwrap_or_else(|| {
            if investment {
                return investment_cash
                    .as_ref()
                    .map(|account| account.name().to_owned())
                    .unwrap_or_else(|| s().opening_holding.to_owned());
            }
            t.own_postings()
                .next()
                .map(|p| p.account.name().to_owned())
                .unwrap_or_default()
        });
    let time = clock::clock_time(t.at.hour() as u8, t.at.minute() as u8);
    let transfer = parsed.as_ref().is_some_and(|p| p.0 == Kind::Transfer);
    // The amount's sign and the leading icon already say "spending"; the
    // account leads so narrow rows truncate the time, not the account.
    let expense = parsed.as_ref().is_some_and(|p| p.0 == Kind::Expense);
    let (title, sub, spoken_sub) = if transfer {
        let payee = t.payee.trim();
        let sub = if payee.is_empty() || payee == kind {
            format!("{kind} · {time}")
        } else {
            format!("{kind} · {time} · {payee}")
        };
        (accounts, sub.clone(), sub)
    } else if expense {
        (
            transaction_title(&t),
            format!("{accounts} · {time}"),
            format!("{kind} · {accounts} · {time}"),
        )
    } else {
        let sub = format!("{kind} · {accounts} · {time}");
        (transaction_title(&t), sub.clone(), sub)
    };
    let currency = parsed
        .as_ref()
        .map(|p| p.1.currency())
        .or_else(|| investment_cash.as_ref().map(|a| a.currency()))
        .or_else(|| t.own_postings().next().map(|p| p.account.currency()))
        .unwrap_or(Currency::CNY);
    let accessibility = format!(
        "{title}, {}, {spoken_sub}",
        crate::ui::currency::decorate(&amount, currency)
    );
    // Keep the amount with its native currency on one baseline when it
    // fits. Larger system text moves it below the record's metadata.
    let amount_chars = amount.len();
    let stacked = move || font_scale() > 1.2 || window().width.0 < 360.0 || amount_chars > 12;
    let inline_amount = amount.clone();
    let amount_style = if system_record {
        Type::Body
    } else {
        Type::Figure
    };
    let title_style = if system_record {
        Type::Callout
    } else {
        Type::Headline
    };
    let tint = if system_record {
        color::MUTED
    } else {
        color::INK
    };
    // A balance check, not a setting: Sliders already names Settings.
    let glyph = if system_record {
        crate::ui::Icon::Check
    } else if investment {
        crate::ui::Icon::Chart
    } else {
        crate::ui::Icon::Wallet
    };
    row_button(on_press)
        .pl(px(crate::pages::rows::LEAD))
        .pr(px(18.0))
        .py(px(if system_record { 8.0 } else { 10.0 }))
        .min_h(px(if system_record { 60.0 } else { 72.0 }))
        .gap(px(14.0))
        .accessibility_label(move || Some(accessibility.clone().into()))
        .child(crate::pages::rows::glyph(
            glyph,
            leading,
            if system_record {
                36.0
            } else {
                crate::pages::rows::THUMB
            },
        ))
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap(px(3.0))
                .child(
                    text(title)
                        .typo(title_style)
                        .text_color(tint)
                        .number_of_lines(if transfer { 2 } else { 1 }),
                )
                .child(
                    text(sub)
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                        .number_of_lines(1),
                )
                .child(when(stacked, move || {
                    crate::ui::currency::amount(amount.clone(), currency, amount_style, tint)
                })),
        )
        .child(when(
            move || !stacked(),
            move || {
                crate::ui::currency::amount(inline_amount.clone(), currency, amount_style, tint)
                    .justify_end()
                    .max_w(px(156.0))
            },
        ))
}
