//! Compact figures used by both live previews and the saved receipt.
use super::summary::{account_line, amount_text, edit_figure, line};
use super::*;
use crate::{
    domain::{capture::Record, format},
    i18n::catalog::copy,
    ui::currency,
};
use navi_finance::{assets, holdings, recognition::Kind};

pub(super) fn day(record: &Record) -> crate::domain::meal::Day {
    match record {
        Record::Money { day, .. }
        | Record::Meal { day, .. }
        | Record::Weight { day, .. }
        | Record::Trade { day, .. }
        | Record::Balance { day, .. }
        | Record::Price { day, .. }
        | Record::Note { day, .. } => *day,
    }
}

pub(super) fn headline(record: &Record) -> (Icon, &'static str, String) {
    match record {
        Record::Money { draft, .. } => (
            Icon::Wallet,
            match draft.kind {
                Kind::Expense => s().spending,
                Kind::Income => s().income,
                Kind::Transfer => s().transfer,
            },
            amount_text(&draft.currency, draft.amount.as_deref().unwrap_or("—")),
        ),
        Record::Meal { estimate, .. } => (
            Icon::Utensils,
            s().meals,
            format!(
                "{} {}",
                format::kcal(crate::domain::nutrition::total(&estimate.foods).kcal),
                s().kcal
            ),
        ),
        Record::Weight { kg, .. } => (Icon::Scale, s().weight, format!("{kg:.1} kg")),
        Record::Trade {
            kind,
            quantity,
            amount,
            currency,
            ..
        } => (
            Icon::Chart,
            crate::pages::holdings::kind_label(*kind),
            if *kind == holdings::Kind::Dividend {
                currency::format(*amount, *currency)
            } else {
                holdings::format_units(*quantity)
            },
        ),
        Record::Balance {
            account, actual, ..
        } => (
            Icon::Check,
            copy("Balance check", "余额核对"),
            currency::format(assets::displayed(account, *actual), account.currency()),
        ),
        Record::Price {
            price, currency, ..
        } => (
            Icon::Chart,
            copy("Manual price", "手动价格"),
            currency::unit_price(*price, *currency),
        ),
        Record::Note { text, .. } => (Icon::Pencil, copy("Review note", "回顾备注"), text.clone()),
    }
}

/// Existing ledger, holding and review records share the same confirmation
/// sheet as meals and spending. Units here match their individual editors.
pub(super) fn extended(
    batch: &Draft,
    index: usize,
    choosing: Signal<Option<accounts::Choice>>,
    editable: bool,
) -> AnyElement {
    let record = &batch.records[index];
    let (glyph, label, value) = headline(record);
    let metric = match record {
        Record::Trade {
            kind: holdings::Kind::Dividend,
            ..
        } => s().dividend_amount,
        Record::Trade { .. } => s().quantity,
        Record::Balance { .. } => s().actual_balance,
        Record::Price { .. } => s().holding_price,
        Record::Note { .. } => copy("Edit review note", "修改回顾备注"),
        _ => return view().into_element(),
    };
    let date = day(record);
    let body = view()
        .gap_2()
        .child(
            view()
                .flex_row()
                .gap_2()
                .items_center()
                .child(icon(glyph, 18.0, color::ACCENT_INK))
                .child(
                    text(label)
                        .typo(Type::Headline)
                        .text_color(color::INK)
                        .flex_1(),
                )
                .child(
                    text(s().long_date(date))
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                ),
        )
        .child(edit_figure(
            view().child(
                text(value)
                    .typo(if matches!(record, Record::Note { .. }) {
                        Type::Body
                    } else {
                        Type::Lead
                    })
                    .tabular_nums()
                    .text_color(color::INK),
            ),
            metric,
            index,
            choosing,
            editable,
        ));
    match record {
        Record::Trade {
            security,
            kind,
            price,
            fee,
            cash,
            currency,
            ..
        } => body
            .child(line(
                s().security_name,
                capture::trade_security_name(security, *currency)
                    .unwrap_or_else(|| security.clone()),
                false,
            ))
            .child((*kind != holdings::Kind::Dividend).then(|| {
                line(
                    s().trade_price,
                    currency::unit_price(*price, *currency),
                    false,
                )
            }))
            .child(line(s().fee, currency::format(*fee, *currency), false))
            .child(
                (*kind != holdings::Kind::Opening).then(|| {
                    account_line(s().cash_account, cash, index, false, choosing, editable)
                }),
            )
            .into_element(),
        Record::Balance {
            account, actual, ..
        } => {
            let book = capture::book_balance(batch, index);
            let delta = book.and_then(|before| actual.checked_sub(before));
            body.child(account_line(
                s().own_account,
                &Some(account.clone()),
                index,
                false,
                choosing,
                editable,
            ))
            .child(book.map(|v| {
                line(
                    s().account_balance,
                    currency::format(assets::displayed(account, v), account.currency()),
                    false,
                )
            }))
            .child(delta.map(|v| {
                line(
                    s().balance_difference,
                    currency::signed(assets::displayed(account, v), account.currency()),
                    false,
                )
            }))
            .into_element()
        }
        Record::Price {
            security, currency, ..
        } => body
            .child(line(
                s().security_name,
                capture::price_security_name(security, *currency)
                    .unwrap_or_else(|| security.clone()),
                false,
            ))
            .child(
                text(|| s().manual_source)
                    .typo(Type::Caption)
                    .text_color(color::MUTED),
            )
            .into_element(),

        _ => body.into_element(),
    }
}

pub(super) fn issue(draft: &Draft, index: usize) -> Option<impl IntoElement> {
    use capture::CaptureIssue::*;
    let label = match capture::record_issue(draft, index)? {
        UnknownSecurity => copy(
            "Use an existing holding or an exact listing ticker and its currency.",
            "请补充已有持仓名称，或准确的证券代码及其币种。",
        ),
        UnknownAccount => s().capture_need_account,
        InvalidTrade => s().holding_error,
        ExistingPrice => copy(
            "A manual price already exists for this date. Edit it in Prices & rates.",
            "这一天已有手动价格，请到价格与汇率中修改。",
        ),
        ExistingNote => copy(
            "This day already has a note. Open Review to edit it.",
            "这一天已有备注，请到回顾中修改。",
        ),
        InvalidDate => copy("Check the date for this record.", "请核对这条记录的日期。"),
        Overflow => s().error_transaction,
    };
    Some(text(label).typo(Type::Subhead).text_color(color::CAUTION))
}
