//! 执行: the ExecutionOS screen — plans with their actions; checking an
//! action off (todo → done) is the progress record. Plans and actions are
//! lightweight captures in sheets.

use std::sync::Arc;

use naviwealth_execution::models::{Action, ActionStatus, Plan, PlanKind, PlanPeriod};
use nsh_base::{SheetEvent, sheet, theme};
use nsh_core::prelude::*;

use crate::state::Services;
use crate::ui;

#[derive(Clone, PartialEq)]
struct PlanRow {
    plan: Plan,
    actions: Vec<Action>,
}

fn fetch_rows(services: &Arc<Services>, rows: Signal<Vec<PlanRow>>, load_error: Signal<String>) {
    let services = services.clone();
    spawn(async move {
        match services.plans_with_actions().await {
            Ok(list) => {
                rows.set(
                    list.into_iter()
                        .map(|(plan, actions)| PlanRow { plan, actions })
                        .collect(),
                );
                load_error.set(String::new());
            }
            Err(e) => load_error.set(e),
        }
    });
}

fn kind_label(kind: PlanKind) -> &'static str {
    match kind {
        PlanKind::Project => "项目",
        PlanKind::Focus => "焦点",
    }
}

fn period_label(period: PlanPeriod) -> &'static str {
    match period {
        PlanPeriod::Week => "周",
        PlanPeriod::Month => "月",
        PlanPeriod::Quarter => "季",
        PlanPeriod::Open => "不限",
    }
}

#[allow(non_snake_case)]
pub fn ExecutionScreen() -> impl IntoElement {
    let services: Arc<Services> = use_context::<Arc<Services>>().expect("services context");

    let rows: Signal<Vec<PlanRow>> = signal(Vec::new());
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

    let plan_sheet_open: Signal<bool> = signal(false);
    // Which plan's action sheet is open (empty = none).
    let action_plan_id: Signal<String> = signal(String::new());

    let action_sheet = action_form_sheet(services.clone(), action_plan_id, data_version.0);

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
                    text("执行")
                        .text_xl()
                        .font_weight(FontWeight::BOLD)
                        .flex_1(),
                )
                .child(ui::primary_button(
                    "＋ 计划",
                    move || plan_sheet_open.set(true),
                    "open-plan-form",
                    None,
                )),
        )
        .child(
            ui::interactive_scroll()
                .flex_1()
                .px_4()
                .pb_4()
                .child(ui::error_line(load_error))
                .child(each(
                    move || rows.get(),
                    |row: &PlanRow| row.plan.id.clone(),
                    {
                        let services = services.clone();
                        move |row: ReadSignal<PlanRow>, _index: ReadSignal<usize>| {
                            plan_row(row, services.clone(), action_plan_id, data_version.0)
                        }
                    },
                )),
        )
        .child(plan_form_sheet(services, plan_sheet_open, data_version.0))
        .child(action_sheet)
}

fn plan_row(
    row: ReadSignal<PlanRow>,
    services: Arc<Services>,
    action_plan_id: Signal<String>,
    reload: Signal<u64>,
) -> impl IntoElement {
    let plan = row;
    let meta = move || {
        let p = plan.get().plan;
        let open = p.status.is_open();
        let status = if open { "" } else { "· 已完结 " };
        format!(
            "{} · {}周期 {}",
            kind_label(p.kind),
            period_label(p.period),
            status
        )
    };
    let actions = move || plan.get().actions.clone();
    let plan_id = move || plan.get().plan.id.clone();

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
                    text(move || plan.get().plan.title.clone())
                        .text_base()
                        .font_weight(FontWeight::MEDIUM)
                        .flex_1(),
                )
                .child(
                    text(meta)
                        .text_xs()
                        .text_color(move || theme().muted_foreground),
                ),
        )
        .child(each(
            actions,
            |action: &Action| action.id.clone(),
            move |action: ReadSignal<Action>, _index: ReadSignal<usize>| {
                action_row(action, services.clone(), reload)
            },
        ))
        .child(view().flex_row().justify_end().child(ui::state_button(
            move || "＋ 动作".to_owned(),
            move || {
                action_plan_id.set(plan_id());
            },
            "",
            false,
        )))
}

fn action_row(
    action: ReadSignal<Action>,
    services: Arc<Services>,
    reload: Signal<u64>,
) -> impl IntoElement {
    let title = move || action.get().title.clone();
    let status = move || action.get().status;
    let is_done = move || status() == ActionStatus::Done;
    let button_label = move || {
        if is_done() {
            "↺ 重新打开".to_owned()
        } else {
            "✓ 完成".to_owned()
        }
    };

    view()
        .flex_row()
        .items_center()
        .gap_2()
        .child(text(title).text_sm().flex_1().text_color(move || {
            if is_done() {
                theme().muted_foreground
            } else {
                theme().foreground
            }
        }))
        .child(
            text(move || {
                match status() {
                    ActionStatus::Todo => "待办",
                    ActionStatus::Doing => "进行中",
                    ActionStatus::Blocked => "受阻",
                    ActionStatus::Done => "已完成",
                    ActionStatus::Dropped => "已放弃",
                }
                .to_owned()
            })
            .text_xs()
            .text_color(move || theme().muted_foreground),
        )
        .child(ui::state_button(
            button_label,
            {
                let services = services.clone();
                move || {
                    let services = services.clone();
                    let action_id = action.get().id.clone();
                    let next = if is_done() {
                        ActionStatus::Todo
                    } else {
                        ActionStatus::Done
                    };
                    spawn(async move {
                        if services.set_action_status(action_id, next).await.is_ok() {
                            reload.update(|v| *v += 1);
                        }
                    });
                }
            },
            "",
            false,
        ))
}

fn plan_form_sheet(
    services: Arc<Services>,
    open: Signal<bool>,
    reload: Signal<u64>,
) -> impl IntoElement {
    let title: Signal<String> = signal(String::new());
    let kind: Signal<PlanKind> = signal(PlanKind::Project);
    let period: Signal<PlanPeriod> = signal(PlanPeriod::Open);
    let save_error: Signal<String> = signal(String::new());
    let saving: Signal<bool> = signal(false);

    let kinds = [(PlanKind::Project, "项目"), (PlanKind::Focus, "焦点")];
    let periods = [
        (PlanPeriod::Week, "周"),
        (PlanPeriod::Month, "月"),
        (PlanPeriod::Quarter, "季"),
        (PlanPeriod::Open, "不限"),
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
                .child(text("新建计划").text_lg().font_weight(FontWeight::SEMIBOLD))
                .child(ui::text_field("名称", "要推进什么", title, "plan-title"))
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
                .child(
                    view()
                        .gap_2()
                        .child(
                            text("周期")
                                .text_sm()
                                .text_color(move || theme().muted_foreground),
                        )
                        .child(view().flex_row().gap_2().children(periods.iter().map(
                            |&(value, label)| {
                                ui::chip(
                                    label.to_owned(),
                                    move || period.get() == value,
                                    move || period.set(value),
                                )
                            },
                        ))),
                )
                .child(ui::error_line(save_error))
                .child(ui::primary_button(
                    "保存",
                    move || {
                        if title.get().trim().is_empty() {
                            save_error.set("请输入计划名称".to_owned());
                            return;
                        }
                        saving.set(true);
                        let services = services.clone();
                        let title_text = title.get().trim().to_owned();
                        let kind_value = kind.get();
                        let period_value = period.get();
                        let save_error = save_error;
                        let saving = saving;
                        let open = open;
                        let reload = reload;
                        let title = title;
                        spawn(async move {
                            match services
                                .create_plan(title_text, kind_value, period_value)
                                .await
                            {
                                Ok(_) => {
                                    saving.set(false);
                                    open.set(false);
                                    title.set(String::new());
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
                    "plan-save",
                    Some(saving),
                )),
        )
}

fn action_form_sheet(
    services: Arc<Services>,
    plan_id: Signal<String>,
    reload: Signal<u64>,
) -> impl IntoElement {
    let title: Signal<String> = signal(String::new());
    let save_error: Signal<String> = signal(String::new());
    let saving: Signal<bool> = signal(false);

    sheet()
        .open(move || {
            let id = plan_id.get();
            (!id.is_empty()).then_some(true)
        })
        .on_open_change(move |event: &SheetEvent| {
            if let SheetEvent::OpenChange(next, _) = event
                && !*next
            {
                plan_id.set(String::new());
            }
        })
        .child(
            view()
                .gap_3()
                .p_5()
                .rounded_t(px(16.0))
                .bg(move || theme().background)
                .child(text("新建动作").text_lg().font_weight(FontWeight::SEMIBOLD))
                .child(ui::text_field(
                    "动作",
                    "下一个具体步骤",
                    title,
                    "action-title",
                ))
                .child(ui::error_line(save_error))
                .child(ui::primary_button(
                    "保存",
                    move || {
                        if title.get().trim().is_empty() {
                            save_error.set("请输入动作内容".to_owned());
                            return;
                        }
                        saving.set(true);
                        let services = services.clone();
                        let title_text = title.get().trim().to_owned();
                        let plan_id_value = plan_id.get();
                        let save_error = save_error;
                        let saving = saving;
                        let reload = reload;
                        let title = title;
                        spawn(async move {
                            match services
                                .create_action(plan_id_value, title_text, None)
                                .await
                            {
                                Ok(_) => {
                                    saving.set(false);
                                    plan_id.set(String::new());
                                    title.set(String::new());
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
                    "action-save",
                    Some(saving),
                )),
        )
}
