//! A saved receipt links each reviewed row to its committed record.
use super::{Sheets, details, flight};
use crate::{
    data::capture,
    domain::{
        capture::{Draft, Record},
        meal::Day,
    },
    i18n::{catalog::copy, s},
    nav::{self, Route},
    pages::{
        finance::finance_editor,
        parts::{status_bar, top_bar},
        review_note,
        today::weight_editor,
    },
    ui::{
        Btn, Icon, Type, Typo, color, icon, space,
        surface::{card, hairline, row_button},
    },
};
use nsh_core::{element::Screen, prelude::*};
use std::rc::Rc;

pub(super) fn view_saved(draft: &Draft, sheets: Sheets) -> impl Fn() + use<> {
    let id = draft.id.clone();
    let records: Rc<[Record]> = draft.records.clone().into();
    move || {
        if let [record] = records.as_ref() {
            open_record(
                capture::record_id(&id, 0),
                record,
                sheets.finance,
                sheets.weight,
            );
        } else {
            nav::push(Route::SavedBatch {
                id: id.clone(),
                records: records.clone(),
            });
        }
    }
}

fn open_record(
    id: String,
    record: &Record,
    finance: Signal<Option<String>>,
    weight: Signal<Option<Day>>,
) {
    nav::select(flight::destination(record));
    match record {
        Record::Money { .. }
            if crate::data::finance::transactions_snapshot()
                .iter()
                .any(|t| t.id == id) =>
        {
            finance.set(Some(id))
        }
        Record::Meal { .. } if crate::data::meals::get(&id).is_some() => {
            nav::push(Route::EditMeal(id))
        }
        Record::Weight { day, .. } if crate::data::weights::on(*day).is_some() => {
            weight.set(Some(*day))
        }
        Record::Money { .. } | Record::Meal { .. } | Record::Weight { .. } => {
            crate::ui::toast::show_toast(s().error_transaction_missing, None)
        }
        Record::Trade { .. } => {
            if let Some(trade) = crate::data::finance::holdings_snapshot()
                .trades
                .iter()
                .find(|t| t.id == id)
            {
                nav::push(Route::SavedTrade {
                    security: trade.security.clone(),
                    trade: id,
                });
            } else {
                crate::ui::toast::show_toast(s().error_transaction_missing, None);
            }
        }
        Record::Note { day, .. } => {
            crate::pages::week_review::locate(*day);
            nav::push(Route::SavedObservation {
                id,
                record: Rc::new(record.clone()),
            });
        }
        Record::Balance { .. } | Record::Price { .. } => {
            nav::push(Route::SavedObservation {
                id,
                record: Rc::new(record.clone()),
            });
        }
    }
}

fn date_label(day: Day) -> String {
    if day.0.year() != crate::data::clock::today().0.year() {
        s().axis_date(day, true)
    } else {
        s().long_date(day)
    }
}

fn subject(record: &Record) -> String {
    match record {
        Record::Meal { estimate, .. } => estimate.title.clone().unwrap_or_default(),
        Record::Money { draft, .. } => match (&draft.account, &draft.other_account) {
            (Some(from), Some(to)) if draft.kind == navi_finance::recognition::Kind::Transfer => {
                format!("{} → {}", from.name(), to.name())
            }
            (Some(account), _) if draft.payee.is_empty() => account.name().to_owned(),
            _ => draft.payee.clone(),
        },
        Record::Trade {
            security, currency, ..
        }
        | Record::Price {
            security, currency, ..
        } => capture::price_security_name(security, *currency).unwrap_or_else(|| security.clone()),
        Record::Balance { account, .. } => account.name().to_string(),
        _ => String::new(),
    }
}

pub(crate) fn batch_page(batch: String, records: Rc<[Record]>) -> Screen {
    let finance = signal(None);
    let weight = signal(None);
    let count = records.len();
    let mut list = card();
    for (index, record) in records.iter().enumerate() {
        let (glyph, kind, figure) = details::headline(record);
        let subject = subject(record);
        let title = if subject.is_empty() {
            kind.to_owned()
        } else {
            format!("{kind} · {subject}")
        };
        let date = date_label(details::day(record));
        let label = format!("{title}, {figure}, {date}");
        let id = capture::record_id(&batch, index);
        let record = record.clone();
        if index != 0 {
            list = list.child(hairline(space::CARD));
        }
        list = list.child(
            row_button(move || open_record(id.clone(), &record, finance, weight))
                .accessibility_label(move || Some(label.clone().into()))
                .child(icon(glyph, 20.0, color::MUTED))
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .gap_1()
                        .child(text(title).typo(Type::Headline).text_color(color::INK))
                        .child(
                            text(figure)
                                .typo(Type::Body)
                                .tabular_nums()
                                .text_color(color::INK),
                        )
                        .child(text(date).typo(Type::Caption).text_color(color::MUTED)),
                )
                .child(icon(Icon::ChevronRight, 16.0, color::MUTED)),
        );
    }
    nsh_base::nav_page()
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(
                    move || s().capture_saved_count(count).into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .py_4()
                            .pb_safe_area_plus(px(20.0))
                            .child(list),
                    ),
                )
                .child(crate::ui::toast::toast_view(|| safe_area().bottom.0 + 12.0))
                .child(finance_editor(finance))
                .child(weight_editor(weight, signal(None))),
        )
}

/// Notes, quoted prices and reconciliations are dated observations. Their
/// receipt stays on that day even when a newer value exists on the account.
pub(crate) fn observation_page(record: Rc<Record>) -> Screen {
    let (_, kind, value) = details::headline(&record);
    let day = details::day(&record);
    let mut body = view()
        .px(px(space::GUTTER))
        .py_4()
        .pb_safe_area_plus(px(20.0))
        .gap_4()
        .child(
            text(date_label(day))
                .typo(Type::Headline)
                .text_color(color::INK),
        );
    if matches!(*record, Record::Note { .. }) {
        body = body.child(review_note::input(day));
    } else {
        body = body
            .child(
                text(subject(&record))
                    .typo(Type::Headline)
                    .text_color(color::INK),
            )
            .child(
                text(value)
                    .typo(Type::Lead)
                    .tabular_nums()
                    .text_color(color::INK),
            );
        let link = match record.as_ref() {
            Record::Balance { account, .. } => Some((
                copy("View account", "查看账户"),
                Route::Account(account.to_string()),
            )),
            Record::Price {
                security, currency, ..
            } => capture::saved_security_id(security, *currency)
                .map(|id| (s().price_history, Route::PricesAndRates(Some(id)))),
            _ => None,
        };
        if let Some((label, route)) = link {
            body = body.child(
                Btn::ghost()
                    .label(move || label.into())
                    .on_press(move || nav::push(route.clone())),
            );
        }
    }
    nsh_base::nav_page()
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(move || kind.into(), nav::pop, None))
                .child(scroll().flex_1().child(body)),
        )
}
