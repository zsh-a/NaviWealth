//! Offline listing search shared by the holding task and explicit link flow.
use crate::{
    data::catalog,
    i18n::{catalog as copy, s},
    ui::{
        Btn, Type, Typo, color,
        field::text_input,
        sheet::{initial_focus, retained, task_sheet},
        surface::{hairline, row_button},
    },
};
use navi_finance::catalog::Entry;
use nsh_core::prelude::*;
use std::time::Duration;

#[derive(Clone, Copy)]
pub struct Search {
    pub query: Signal<String>,
    settled: Signal<String>,
    limit: Signal<usize>,
}
impl Search {
    pub fn new() -> Self {
        let query = signal(String::new());
        let settled = signal(String::new());
        let limit = signal(16);
        let generation = stored(0u64);
        effect(move || {
            let next = query.get();
            let revision = generation.with(|n| *n + 1);
            generation.replace(revision);
            if next.trim().is_empty() {
                batch(|| {
                    settled.set(String::new());
                    limit.set(16);
                });
                return;
            }
            spawn(async move {
                timer(Duration::from_millis(120)).await;
                if generation.with(|n| *n) == revision && query.get_untracked() == next {
                    batch(|| {
                        settled.set(next);
                        limit.set(16);
                    });
                }
            });
        });
        Self {
            query,
            settled,
            limit,
        }
    }
    pub fn input(self) -> impl IntoElement {
        crate::data::tasks::spawn_app(async { catalog::refresh().await });
        set_interval(Duration::from_secs(300), || {
            if lifecycle() == nsh_core::platform::Lifecycle::Active {
                crate::data::tasks::spawn_app(catalog::refresh());
            }
        });
        let focus = initial_focus();
        text_input(self.query)
            .test_id("security-search")
            .label(copy::search)
            .placeholder(copy::search)
            .element_ref(&focus)
    }
    pub fn results(self, choose: impl Fn(Entry) + Copy + 'static) -> impl IntoElement {
        let entries = signal(Vec::<Entry>::new());
        effect(move || {
            let query = self.settled.get();
            entries.set(if query.trim().is_empty() {
                Vec::new()
            } else {
                catalog::search_page(&query, 0, self.limit.get() + 1)
            });
        });
        view()
            .gap_2()
            .child(when(
                move || self.settled.get().trim().is_empty(),
                || {
                    text(copy::hint)
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                },
            ))
            .child(when(
                move || !self.settled.get().trim().is_empty() && entries.get().is_empty(),
                || {
                    text(|| {
                        if catalog::available() {
                            copy::empty()
                        } else if catalog::status() == catalog::Status::Failed {
                            copy::copy("Catalog unavailable", "证券目录暂不可用")
                        } else {
                            copy::copy("Loading listings…", "正在载入证券目录…")
                        }
                    })
                    .typo(Type::Body)
                    .text_color(color::MUTED)
                },
            ))
            .child(each(
                move || {
                    entries
                        .get()
                        .into_iter()
                        .take(self.limit.get())
                        .collect::<Vec<_>>()
                },
                |entry: &Entry| format!("{}:{}", entry.market, entry.symbol),
                move |entry, _| {
                    dynamic(move || {
                        let entry = entry.get();
                        untracked(move || {
                            let label = format!(
                                "{} · {} · {}",
                                copy::market(&entry.market),
                                entry.symbol,
                                entry.currency
                            );
                            let name = entry.name().to_owned();
                            let supported = entry.supported();
                            let chosen = entry.clone();
                            view()
                                .child(
                                    row_button(move || {
                                        if supported {
                                            choose(chosen.clone());
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
                        })
                    })
                },
            ))
            .child(when(
                move || entries.get().len() > self.limit.get(),
                move || {
                    Btn::ghost()
                        .label(|| copy::copy("Show more", "显示更多").into())
                        .on_press(move || self.limit.update(|n| *n += 16))
                },
            ))
    }
}
pub fn search_actions(manual: impl Fn() + Copy + 'static) -> impl IntoElement {
    Btn::ghost()
        .size(crate::ui::Size::Small)
        .label(|| copy::manual().into())
        .on_press(manual)
        .min_h(px(48.0))
        .px_3()
}
pub fn selector(open: Signal<bool>, choose: impl Fn(Entry) + Copy + 'static) -> impl IntoElement {
    retained(
        move || open.get().then_some(()),
        move |_| {
            let search = Search::new();
            let close = move || {
                dismiss_keyboard();
                open.set(false);
            };
            task_sheet(
                move || open.get(),
                close,
                view()
                    .gap_3()
                    .child(
                        view()
                            .flex_row()
                            .items_center()
                            .child(
                                text(copy::title)
                                    .typo(Type::Title)
                                    .text_color(color::INK)
                                    .flex_1(),
                            )
                            .child(Btn::ghost().label(|| s().cancel.into()).on_press(close)),
                    )
                    .child(search.input()),
                search.results(move |entry| {
                    choose(entry);
                    close();
                }),
                search_actions(close),
            )
            .into_element()
        },
    )
}
