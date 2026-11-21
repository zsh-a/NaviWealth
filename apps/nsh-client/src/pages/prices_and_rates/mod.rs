//! One workspace for dated prices, rates and their provenance.
mod rates;

use crate::{
    data::{clock::observation_time, finance, history},
    i18n::{market::source_label, s, statement_import::copy},
    nav,
    ui::{
        Btn, Type, Typo, color,
        segmented::{Segment, segmented},
        space,
        surface::{disclosure_chevron, hairline, row_button},
    },
};
use navi_finance::holdings::format_units;
use navi_finance::{
    currency::Currency,
    history::{DailyBar, Instrument, PriceChange},
};
use nsh_core::{element::Screen, prelude::*};

pub(crate) fn title() -> &'static str {
    copy("Prices & rates", "价格与汇率")
}

#[derive(Clone, Copy, PartialEq)]
enum Section {
    Rates,
    Closes,
    Changes,
}

pub fn page(security: Option<String>) -> Screen {
    let scoped = security.is_some();
    let security = stored(security);
    let section = signal(if scoped {
        Section::Closes
    } else {
        Section::Rates
    });
    let mut segments = Vec::new();
    if !scoped {
        segments.push(Segment::new(Section::Rates, || {
            copy("Rates", "汇率").into()
        }));
    }
    segments.push(Segment::new(Section::Closes, || {
        copy("Daily closes", "每日收盘").into()
    }));
    segments.push(Segment::new(Section::Changes, || {
        copy("Changes", "变更记录").into()
    }));
    nsh_base::nav_page()
        .header_visible(false)
        .status_bar(super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::parts::top_bar(
                    move || if scoped { s().price_history } else { title() }.into(),
                    nav::pop,
                    None,
                ))
                .child(view().px(px(space::GUTTER)).pb_3().child(segmented(
                    segments,
                    move || section.get(),
                    move |v| section.set(v),
                )))
                .child(dynamic(move || {
                    let selected = security.get();
                    let tab = section.get();
                    untracked(move || {
                        let content = match tab {
                            Section::Rates => rates::panel().into_element(),
                            Section::Closes => archive(
                                move |limit| history::daily_history(selected.as_deref(), limit),
                                bar_row,
                                || copy("No daily closes yet", "暂无收盘价"),
                            )
                            .into_element(),
                            Section::Changes => archive(
                                move |limit| history::changes(selected.as_deref(), limit),
                                audit_row,
                                || copy("No changes yet", "暂无变更记录"),
                            )
                            .into_element(),
                        };
                        scroll()
                            .flex_1()
                            .child(
                                view()
                                    .px(px(space::GUTTER))
                                    .pb_safe_area_plus(px(24.0))
                                    .child(content),
                            )
                            .into_element()
                    })
                })),
        )
}

fn archive<T: 'static, E: IntoElement + 'static>(
    read: impl Fn(i64) -> Result<Vec<T>, String> + 'static,
    row: fn(T) -> E,
    empty: fn() -> &'static str,
) -> impl IntoElement {
    let limit = signal(30usize);
    dynamic(move || {
        let _ = finance::holdings_snapshot();
        let _ = finance::rates_snapshot();
        history::watch();
        let count = limit.get();
        let result = read(count as i64 + 1);
        untracked(move || {
            let mut list = view().gap_1();
            match result {
                Err(_) => {
                    list = list.child(
                        text(copy("Could not load records", "暂时无法读取记录"))
                            .typo(Type::Body)
                            .text_color(color::DANGER),
                    )
                }
                Ok(rows) if rows.is_empty() => {
                    list = list.child(
                        text(empty())
                            .typo(Type::Body)
                            .text_color(color::MUTED)
                            .py_5(),
                    )
                }
                Ok(rows) => {
                    let more = rows.len() > count;
                    list = list.children(rows.into_iter().take(count).map(row));
                    if more {
                        list = list.child(
                            Btn::ghost()
                                .label(|| copy("Show more", "查看更多").into())
                                .on_press(move || limit.update(|n| *n += 30)),
                        );
                    }
                }
            }
            list.into_element()
        })
    })
}

fn observation_row(
    title: String,
    detail: String,
    value: String,
    expanded: Signal<bool>,
) -> impl IntoElement {
    row_button(move || expanded.update(|v| *v = !*v))
        .px_0()
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(text(title).typo(Type::Headline).text_color(color::INK))
                .child(text(detail).typo(Type::Caption).text_color(color::MUTED)),
        )
        .child(
            text(value)
                .typo(Type::Body)
                .tabular_nums()
                .text_color(color::INK),
        )
        .child(disclosure_chevron(expanded))
}

fn bar_row(rows: Vec<DailyBar>) -> impl IntoElement {
    let last = rows.last().expect("group is nonempty").clone();
    let expanded = signal(false);
    let title = format!("{} · {}", last.symbol, last.day);
    let value = crate::ui::currency::observed_price(last.close, Currency::parse(&last.currency));
    let detail = format!(
        "{} · {} {}",
        source_label(&last.provider),
        rows.len(),
        copy("versions", "个版本")
    );
    view()
        .child(observation_row(title, detail, value, expanded))
        .child(dynamic(move || {
            let mut v = view().gap_2();
            if expanded.get() {
                for r in rows.iter().rev() {
                    v = v
                        .child(
                            text(format!(
                                "{} {} · {} {} · {} {} · {} {}",
                                copy("Open", "开"),
                                format_units(r.open),
                                copy("High", "高"),
                                format_units(r.high),
                                copy("Low", "低"),
                                format_units(r.low),
                                copy("Close", "收"),
                                format_units(r.close)
                            ))
                            .typo(Type::Subhead)
                            .text_color(color::BODY),
                        )
                        .child(
                            text(format!(
                                "{} · {} {}{}",
                                source_label(&r.provider),
                                copy("Fetched", "获取于"),
                                observation_time(r.fetched_at),
                                r.volume
                                    .map(|n| format!(
                                        " · {} {n}",
                                        copy("Volume (provider units)", "成交量（源单位）")
                                    ))
                                    .unwrap_or_default()
                            ))
                            .typo(Type::Caption)
                            .text_color(color::MUTED),
                        );
                }
            }
            v.into_element()
        }))
        .child(hairline(0.0))
}

fn audit_row(row: PriceChange) -> impl IntoElement {
    let (label, amount) = match row.instrument {
        Instrument::ExchangeRate(currency) => {
            (format!("{currency} → CNY"), format_units(row.value))
        }
        Instrument::Security { name, currency } => (
            name,
            crate::ui::currency::observed_price(row.value, currency),
        ),
    };
    let expanded = signal(false);
    let detail = format!(
        "{} · {}{}",
        row.day,
        source_label(row.source.as_deref().unwrap_or_default()),
        if row.previous_binding {
            copy(" · Previous binding", " · 原绑定")
        } else {
            ""
        }
    );
    let provenance = format!(
        "{} {}{}",
        if row.baseline {
            copy("Existing record retained at", "原有记录留存于")
        } else {
            copy("Recorded at", "记录于")
        },
        observation_time(row.received_at),
        row.symbol
            .map(|symbol| format!(" · {symbol}"))
            .unwrap_or_default()
    );
    view()
        .child(observation_row(label, detail, amount, expanded))
        .child(when(
            move || expanded.get(),
            move || {
                text(provenance.clone())
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .pb_3()
            },
        ))
        .child(hairline(0.0))
}
