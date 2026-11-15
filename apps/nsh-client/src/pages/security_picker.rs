//! Compact, offline-first listing selection, with explicit supported-market states.
use crate::{
    data::catalog,
    i18n::{catalog as copy, s},
    ui::{
        Btn, Type, Typo, color,
        field::{field, text_input},
        sheet::task_sheet,
        surface::{hairline, row_button},
    },
};
use finance_core::catalog::Entry;
use nsh_core::prelude::*;
pub fn selector(open: Signal<bool>, choose: impl Fn(Entry) + Copy + 'static) -> impl IntoElement {
    dynamic(move || {
        if !open.get() {
            return view().into_element();
        }
        untracked(move || {
            crate::data::tasks::spawn_app(async { catalog::refresh(false).await });
            let query = signal(String::new());
            let close = move || {
                dismiss_keyboard();
                open.set(false)
            };
            let header = view()
                .flex_row()
                .items_center()
                .child(
                    text(copy::title)
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .flex_1(),
                )
                .child(Btn::ghost().label(|| s().cancel.into()).on_press(close));
            let body = view()
                .gap_3()
                .child(field(
                    copy::search,
                    text_input(query)
                        .label(copy::search)
                        .placeholder(copy::search),
                ))
                .child(
                    text(copy::hint)
                        .typo(Type::Subhead)
                        .text_color(color::MUTED),
                )
                .child(dynamic(move || {
                    let q = query.get();
                    let entries = catalog::search(&q);
                    untracked(move || {
                        if q.trim().is_empty() {
                            return view().into_element();
                        }
                        if entries.is_empty() {
                            return text(copy::empty)
                                .typo(Type::Body)
                                .text_color(color::MUTED)
                                .into_element();
                        }
                        view()
                            .children(entries.into_iter().map(move |entry| {
                                let label = format!(
                                    "{} · {} · {}",
                                    copy::market(&entry.market),
                                    entry.symbol,
                                    entry.currency
                                );
                                let supported = entry.supported();
                                let name = entry.name().to_owned();
                                let chosen = entry.clone();
                                view()
                                    .child(
                                        row_button(move || {
                                            if supported {
                                                choose(chosen.clone());
                                                close()
                                            }
                                        })
                                        .accessibility_label(move || {
                                            Some(format!("{name}, {label}").into())
                                        })
                                        .disabled(!supported)
                                        .px_0()
                                        .min_h(px(56.0))
                                        .child(
                                            view()
                                                .flex_1()
                                                .min_w(px(0.0))
                                                .gap_1()
                                                .child(
                                                    text(entry.name().to_owned())
                                                        .typo(Type::Headline)
                                                        .text_color(color::INK),
                                                )
                                                .child(
                                                    text(format!(
                                                        "{} · {} · {}",
                                                        copy::market(&entry.market),
                                                        entry.symbol,
                                                        entry.currency
                                                    ))
                                                    .typo(Type::Caption)
                                                    .text_color(color::MUTED),
                                                )
                                                .child((!supported).then(|| {
                                                    text(copy::unsupported)
                                                        .typo(Type::Caption)
                                                        .text_color(color::MUTED)
                                                })),
                                        ),
                                    )
                                    .child(hairline(0.0))
                            }))
                            .into_element()
                    })
                }));
            let action = view()
                .gap_2()
                .child(
                    text(move || {
                        format!(
                            "{} · {}",
                            catalog::version(),
                            copy::status(catalog::status())
                        )
                    })
                    .typo(Type::Caption)
                    .text_color(color::MUTED),
                )
                .child(
                    Btn::tonal()
                        .label(|| copy::refresh().into())
                        .disabled(move || catalog::status() == catalog::Status::Updating)
                        .on_press(|| {
                            spawn(async { catalog::refresh(true).await });
                        }),
                )
                .child(Btn::ghost().label(|| copy::manual().into()).on_press(close));
            task_sheet(move || open.get(), close, header, body, action).into_element()
        })
    })
}
