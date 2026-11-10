//! 账本: recent journal entries with their posting legs.

use std::sync::Arc;

use nsh_base::theme;
use nsh_core::prelude::*;

use crate::state::Services;
use crate::ui;

fn day_text(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}")
}

type EntryItem = naviwealth_finance::repos::journal_repository::EntryWithPostings;

#[allow(non_snake_case)]
pub fn LedgerScreen() -> impl IntoElement {
    let services: Arc<Services> = use_context::<Arc<Services>>().expect("services context");

    let entries: Signal<Vec<EntryItem>> = signal(Vec::new());
    let names: Signal<Vec<(String, String)>> = signal(Vec::new());
    let load_error: Signal<String> = signal(String::new());
    let data_version = use_context::<crate::state::DataVersion>().expect("data version");

    {
        let services = services.clone();
        // Reload on mount and whenever any write bumps the shared
        // data version.
        effect(move || {
            let _generation = data_version.0.get();
            let services = services.clone();
            spawn(async move {
                let (entry_list, name_list) =
                    tokio::join!(services.recent_entries(100), services.account_names());
                match (entry_list, name_list) {
                    (Ok(e), Ok(n)) => {
                        // Names first: row re-renders read the names map
                        // that is current when the entries land.
                        names.set(n);
                        entries.set(e);
                        load_error.set(String::new());
                    }
                    (Err(e), _) | (_, Err(e)) => load_error.set(e),
                }
            });
        });
    }

    view()
        .flex_1()
        .child(
            view()
                .px_4()
                .py_3()
                .child(text("账本").text_xl().font_weight(FontWeight::BOLD)),
        )
        .child(
            scroll()
                .flex_1()
                .px_4()
                .pb_4()
                .child(ui::error_line(load_error))
                .child(each(
                    move || entries.get(),
                    |item: &EntryItem| item.entry.id.clone(),
                    move |item: ReadSignal<EntryItem>, _index: ReadSignal<usize>| {
                        entry_card(item, names)
                    },
                )),
        )
}

fn entry_card(
    item: ReadSignal<EntryItem>,
    names: Signal<Vec<(String, String)>>,
) -> impl IntoElement {
    let entry = item;
    let legs = move || {
        entry
            .get()
            .postings
            .iter()
            .map(|p| {
                let account = names
                    .with(|list| {
                        list.iter()
                            .find(|(id, _)| *id == p.account_id)
                            .map(|(_, name)| name.clone())
                    })
                    .unwrap_or_else(|| p.account_id.clone());
                format!("{account}  {} {}", p.units, p.unit)
            })
            .collect::<Vec<_>>()
    };
    let legs_view = view().gap_1().children(legs().into_iter().map(|leg| {
        text(leg)
            .text_sm()
            .tabular_nums()
            .text_color(move || theme().muted_foreground)
    }));
    view()
        .gap_2()
        .p_4()
        .rounded(move || px(crate::ui::card_radius()))
        .bg(move || theme().card)
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(
                    text(move || day_text(entry.get().entry.date))
                        .text_sm()
                        .tabular_nums()
                        .text_color(move || theme().muted_foreground),
                )
                .child(
                    text(move || entry.get().entry.narration.clone())
                        .text_base()
                        .font_weight(FontWeight::MEDIUM)
                        .flex_1(),
                )
                .child(
                    text(move || entry.get().entry.payee.clone().unwrap_or_default())
                        .text_sm()
                        .text_color(move || theme().muted_foreground),
                ),
        )
        .child(legs_view)
}
