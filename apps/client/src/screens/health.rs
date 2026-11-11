//! 健康: the HealthOS screen — manual metric capture (steps / sleep /
//! weight) and the recent list. No platform integration in this phase:
//! HealthKit / Health Connect stay behind the platform stub.

use std::str::FromStr;
use std::sync::Arc;

use naviwealth_health::models::{Metric, MetricKind};
use nsh_base::{SheetEvent, sheet, theme};
use nsh_core::prelude::*;
use rust_decimal::Decimal;

use crate::state::Services;
use crate::ui;

fn kind_label(kind: MetricKind) -> &'static str {
    match kind {
        MetricKind::Steps => "步数",
        MetricKind::Sleep => "睡眠",
        MetricKind::Weight => "体重",
    }
}

fn fetch_rows(services: &Arc<Services>, rows: Signal<Vec<Metric>>, load_error: Signal<String>) {
    let services = services.clone();
    spawn(async move {
        match services.recent_metrics(50).await {
            Ok(list) => {
                rows.set(list);
                load_error.set(String::new());
            }
            Err(e) => load_error.set(e),
        }
    });
}

#[allow(non_snake_case)]
pub fn HealthScreen() -> impl IntoElement {
    let services: Arc<Services> = use_context::<Arc<Services>>().expect("services context");

    let rows: Signal<Vec<Metric>> = signal(Vec::new());
    let load_error: Signal<String> = signal(String::new());
    let data_version = use_context::<crate::state::DataVersion>().expect("data version");

    fetch_rows(&services, rows, load_error);
    {
        let services = services.clone();
        effect(move || {
            let _generation = data_version.0.get();
            fetch_rows(&services, rows, load_error);
        });
    }

    let sheet_open: Signal<bool> = signal(false);

    view()
        .flex_1()
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_3()
                .px_4()
                .py_3()
                .child(
                    text("健康")
                        .text_xl()
                        .font_weight(FontWeight::BOLD)
                        .flex_1(),
                )
                .child(ui::primary_button(
                    "＋ 记录",
                    move || sheet_open.set(true),
                    "open-metric-form",
                    None,
                )),
        )
        .child(
            scroll()
                .flex_1()
                .px_4()
                .pb_4()
                .child(ui::error_line(load_error))
                .child(each(
                    move || rows.get(),
                    |metric: &Metric| metric.id.clone(),
                    move |metric: ReadSignal<Metric>, _index: ReadSignal<usize>| metric_row(metric),
                )),
        )
        .child(metric_form_sheet(services, sheet_open, data_version.0))
}

fn metric_row(metric: ReadSignal<Metric>) -> impl IntoElement {
    let label = move || {
        let m = metric.get();
        format!("{}　{} {}", kind_label(m.kind), m.quantity, m.unit)
    };
    let meta = move || {
        let m = metric.get();
        let source = m
            .source
            .as_deref()
            .filter(|s| !s.is_empty())
            .unwrap_or("未知来源");
        format!("{} · {}", ui::ymd(m.recorded_at), source)
    };
    view()
        .flex_row()
        .items_center()
        .gap_3()
        .p_4()
        .rounded(move || px(crate::ui::card_radius()))
        .bg(move || theme().card)
        .child(
            text(label)
                .text_base()
                .font_weight(FontWeight::MEDIUM)
                .flex_1()
                .tabular_nums(),
        )
        .child(
            text(meta)
                .text_xs()
                .text_color(move || theme().muted_foreground),
        )
}

fn metric_form_sheet(
    services: Arc<Services>,
    open: Signal<bool>,
    reload: Signal<u64>,
) -> impl IntoElement {
    let kind: Signal<MetricKind> = signal(MetricKind::Steps);
    let quantity: Signal<String> = signal(String::new());
    let save_error: Signal<String> = signal(String::new());
    let saving: Signal<bool> = signal(false);

    let kinds = [
        (MetricKind::Steps, "步数"),
        (MetricKind::Sleep, "睡眠（分钟）"),
        (MetricKind::Weight, "体重（kg）"),
    ];

    sheet()
        .open(move || Some(open.get()))
        .on_open_change(move |event: &SheetEvent| {
            if let SheetEvent::OpenChange(next, _) = event {
                open.set(*next);
            }
        })
        .child(
            view()
                .gap_3()
                .p_5()
                .rounded_t(px(16.0))
                .bg(move || theme().background)
                .child(text("记录指标").text_lg().font_weight(FontWeight::SEMIBOLD))
                .child(
                    view()
                        .gap_2()
                        .child(
                            text("类型")
                                .text_sm()
                                .text_color(move || theme().muted_foreground),
                        )
                        .child(view().flex_row().gap_2().children(kinds.iter().map(
                            |&(value, label)| {
                                ui::chip(
                                    label.to_owned(),
                                    move || kind.get() == value,
                                    move || kind.set(value),
                                )
                            },
                        ))),
                )
                .child(ui::text_field(
                    "数值",
                    "例如 8432 / 420 / 72.5",
                    quantity,
                    "metric-quantity",
                ))
                .child(ui::error_line(save_error))
                .child(ui::primary_button(
                    "保存",
                    move || {
                        let parsed = Decimal::from_str(quantity.get().trim()).ok();
                        match parsed {
                            None => {
                                save_error.set("请输入有效的数值".to_owned());
                                return;
                            }
                            Some(value) if value.is_sign_negative() => {
                                save_error.set("数值不能为负".to_owned());
                                return;
                            }
                            Some(_) => {}
                        }
                        saving.set(true);
                        let services = services.clone();
                        let kind_value = kind.get();
                        let value = Decimal::from_str(quantity.get().trim()).unwrap_or_default();
                        let save_error = save_error;
                        let saving = saving;
                        let open = open;
                        let reload = reload;
                        let quantity = quantity;
                        spawn(async move {
                            match services.record_metric(kind_value, value).await {
                                Ok(_) => {
                                    saving.set(false);
                                    open.set(false);
                                    quantity.set(String::new());
                                    save_error.set(String::new());
                                    reload.update(|v| *v += 1);
                                }
                                Err(e) => {
                                    saving.set(false);
                                    save_error.set(e);
                                }
                            }
                        });
                    },
                    "metric-save",
                    Some(saving),
                )),
        )
}
