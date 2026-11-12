//! Reviewed statements, financial inbox, reconciliation and month-end evidence.
use crate::{
    finance_operations::*,
    finance_ui::{self as fui, Field, Values},
    ui,
};
use nsh_base::theme;
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::{cell::Cell, future::Future, pin::Pin, rc::Rc};
#[path = "operations_ui/close.rs"]
mod close;
#[path = "operations_ui/imports.rs"]
mod imports;
#[path = "operations_ui/inbox.rs"]
mod inbox;
#[path = "operations_ui/reconciliation.rs"]
mod reconciliation;

pub fn render(path: String) -> AnyElement {
    let parts = path
        .trim_matches('/')
        .split('/')
        .map(str::to_owned)
        .collect::<Vec<_>>();
    match parts.get(1).map(String::as_str) {
        Some("import") => imports::render(parts),
        Some("reconcile") => reconciliation::render(parts),
        Some("close") => close::render(parts),
        Some("inbox") => inbox::render(parts),
        _ => fui::page("财务操作", copy("当前操作地址无法识别，请返回活动页重试。")),
    }
}
type LoadFuture<T> = Pin<Box<dyn Future<Output = Result<T, String>>>>;
fn loaded<T: Clone + PartialEq + 'static>(
    title: &'static str,
    fetch: impl Fn() -> LoadFuture<T> + 'static,
    render: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    loaded_mode(title, false, fetch, render)
}
fn loaded_mode<T: Clone + PartialEq + 'static>(
    title: &'static str,
    freeze_draft: bool,
    fetch: impl Fn() -> LoadFuture<T> + 'static,
    render: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    let data = signal(None::<T>);
    let error = signal(String::new());
    let loading = signal(true);
    let retry = signal(0u64);
    let version = use_context::<crate::state::DataVersion>()
        .expect("data version")
        .0;
    let sequence = Rc::new(Cell::new(0u64));
    effect(move || {
        if !freeze_draft {
            version.get();
        }
        retry.get();
        let next = sequence.get() + 1;
        sequence.set(next);
        let current = sequence.clone();
        let future = fetch();
        loading.set(true);
        error.set(String::new());
        spawn(async move {
            match future.await {
                Ok(v) if current.get() == next => data.set(Some(v)),
                Err(e) if current.get() == next => error.set(e),
                _ => {}
            }
            if current.get() == next {
                loading.set(false);
            }
        });
    });
    dynamic(move || {
        if loading.get() {
            return fui::page(title, copy("正在读取本地财务数据…"));
        }
        if !error.get().is_empty() {
            return fui::page(
                title,
                view().gap_3().child(copy(&error.get())).child(fui::action(
                    "重新读取",
                    "operations-retry",
                    move || retry.update(|n| *n += 1),
                )),
            );
        }
        if let Some(v) = data.get() {
            render(v)
        } else {
            fui::page(title, copy("暂无可读取的数据，请重试。"))
        }
    })
    .into_element()
}
fn copy(message: &str) -> AnyElement {
    text(message.to_owned())
        .text_sm()
        .text_color(move || theme().muted_foreground)
        .into_element()
}
fn heading(message: impl Into<String>) -> AnyElement {
    text(message.into())
        .text_base()
        .font_weight(FontWeight::SEMIBOLD)
        .into_element()
}
fn detail(label: &str, value: impl Into<String>) -> AnyElement {
    let value = value.into();
    let tone = value.clone();
    view()
        .flex_row()
        .gap_3()
        .py_2()
        .child(
            text(label.to_owned())
                .text_sm()
                .text_color(move || theme().muted_foreground)
                .w(px(88.0)),
        )
        .child(
            text(value)
                .text_color(move || ui::money_tone(&tone))
                .text_sm()
                .flex_1()
                .min_w(px(0.0))
                .tabular_nums(),
        )
        .into_element()
}
fn go(label: &'static str, id: &'static str, path: String) -> AnyElement {
    fui::action(label, id, move || fui::navigate(path.clone()))
}
fn mutation(
    label: &'static str,
    id: &'static str,
    message: &'static str,
    action: impl Fn() -> fui::SaveFuture + 'static,
) -> AnyElement {
    let busy = signal(false);
    let error = signal(String::new());
    view()
        .gap_2()
        .child(ui::primary_button(
            label,
            move || {
                if busy.get() {
                    return;
                }
                busy.set(true);
                error.set(String::new());
                fui::notice("");
                let future = action();
                spawn(async move {
                    match future.await {
                        Ok(target) => {
                            busy.set(false);
                            if use_context::<fui::Feedback>().is_none_or(|f| f.0.get().is_empty()) {
                                fui::notice(message);
                            }
                            fui::finish(target, false);
                        }
                        Err(e) => {
                            error.set(e.strip_prefix("invalid data: ").unwrap_or(&e).to_owned());
                            busy.set(false);
                        }
                    }
                });
            },
            id,
            Some(busy),
        ))
        .child(when(move || busy.get(), || copy("正在保存，请稍候…")))
        .child(ui::error_line(error))
        .into_element()
}
fn previous_month() -> String {
    let now = chrono::Local::now().date_naive();
    let first = now.with_day(1).unwrap();
    (first - chrono::Duration::days(1))
        .format("%Y-%m")
        .to_string()
}
use chrono::Datelike;
fn amount(value: Decimal, currency: &str) -> String {
    format!("{} {currency}", ui::money_for(value, currency))
}
fn read_optional(v: &Values, id: &'static str) -> Option<String> {
    v.get(id)
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
}
fn required(v: &Values, id: &'static str, label: &str) -> Result<String, String> {
    read_optional(v, id).ok_or_else(|| format!("请填写{label}"))
}
fn decimal(v: &Values, id: &'static str, label: &str) -> Result<Decimal, String> {
    Decimal::from_str_exact(&required(v, id, label)?)
        .map_err(|_| format!("{label}须为有效十进制数"))
}
fn date(v: &Values, id: &'static str) -> Result<i64, String> {
    ui::date_to_secs(&required(v, id, "日期")?)
        .ok_or_else(|| "日期须为有效的 YYYY-MM-DD".to_owned())
}

#[cfg(test)]
#[path = "operations_ui/tests.rs"]
mod tests;
