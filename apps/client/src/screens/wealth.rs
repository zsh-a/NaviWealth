//! Native wealth workspace: authored assets, exact positions, valuations and trades.
use crate::{finance_ui as fui, ui};
use fui::Field;
use naviwealth_finance::{
    models::{Account, AccountSide},
    wealth::*,
};
use nsh_base::theme;
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::{future::Future, pin::Pin};

type Fetch<T> = Pin<Box<dyn Future<Output = Result<T, String>>>>;
/// Form dependencies load once. A background refresh cannot erase an authored draft.
fn loaded_form<T: Clone + PartialEq + 'static>(
    title: impl Into<String>,
    fetch: impl Fn() -> Fetch<T> + 'static,
    display: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    let title = title.into();
    let value = signal(None::<T>);
    let error = signal(String::new());
    let retry = signal(0u64);
    effect(move || {
        retry.get();
        error.set(String::new());
        let task = fetch();
        spawn(async move {
            match task.await {
                Ok(v) => {
                    value.try_set(Some(v));
                }
                Err(e) => {
                    error.try_set(e);
                }
            }
        });
    });
    dynamic(move || match value.get() {
        Some(v) => display(v),
        None => fui::page(
            title.clone(),
            view()
                .gap_3()
                .child(when(move || error.get().is_empty(), ui::skeleton))
                .child(ui::error_line(error))
                .child(when(
                    move || !error.get().is_empty(),
                    move || {
                        fui::action("重新读取", "wealth-form-retry", move || {
                            retry.update(|v| *v += 1)
                        })
                    },
                )),
        ),
    })
    .into_element()
}
fn loaded<T: Clone + PartialEq + 'static>(
    fetch: impl Fn() -> Fetch<T> + 'static,
    display: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    let value = signal(None::<T>);
    let error = signal(String::new());
    let loading = signal(true);
    let retry = signal(0u64);
    let serial = signal(0u64);
    let version = use_context::<crate::state::DataVersion>()
        .expect("data version")
        .0;
    effect(move || {
        version.get();
        retry.get();
        serial.update(|v| *v += 1);
        let current = serial.get_untracked();
        loading.set(true);
        error.set(String::new());
        let task = fetch();
        spawn(async move {
            let result = task.await;
            if serial.try_get() != Some(current) {
                return;
            }
            match result {
                Ok(v) => {
                    value.try_set(Some(v));
                }
                Err(e) => {
                    error.try_set(e);
                }
            }
            loading.try_set(false);
        });
    });
    view()
        .gap_3()
        .child(when(
            move || loading.get() && value.get().is_none(),
            ui::skeleton,
        ))
        .child(when(
            move || !error.get().is_empty(),
            move || {
                view()
                    .gap_2()
                    .child(ui::error_line(error))
                    .child(fui::action("重新读取", "wealth-retry", move || {
                        retry.update(|v| *v += 1)
                    }))
            },
        ))
        .child(dynamic(move || match value.get() {
            Some(v) => display(v),
            None => view().into_element(),
        }))
        .into_element()
}
fn optional(s: String) -> Option<String> {
    let s = s.trim();
    (!s.is_empty()).then(|| s.to_owned())
}
fn amount(value: Option<Decimal>, currency: &str) -> String {
    value
        .map(|v| format!("{} {currency}", ui::money_for(v, currency)))
        .unwrap_or_else(|| "暂不可估值".into())
}
fn note(s: impl Into<String>) -> AnyElement {
    text(s.into())
        .text_sm()
        .text_color(move || theme().muted_foreground)
        .into_element()
}
fn asset_kind(kind: &str) -> &'static str {
    match kind {
        "stock" => "股票",
        "etf" => "ETF",
        "mutual_fund" => "基金",
        "bond" => "债券",
        "crypto" => "数字资产",
        "cash" => "现金资产",
        "real_estate" => "房产",
        "vehicle" => "车辆",
        _ => "其他资产",
    }
}
fn kind_key(kind: OperationKind) -> &'static str {
    match kind {
        OperationKind::Opening => "opening",
        OperationKind::Buy => "buy",
        OperationKind::Sell => "sell",
        OperationKind::Dividend => "dividend",
        OperationKind::Split => "split",
    }
}
fn operation_kind(key: &str) -> Result<OperationKind, String> {
    match key {
        "opening" => Ok(OperationKind::Opening),
        "buy" => Ok(OperationKind::Buy),
        "sell" => Ok(OperationKind::Sell),
        "dividend" => Ok(OperationKind::Dividend),
        "split" => Ok(OperationKind::Split),
        _ => Err("请选择交易类型".into()),
    }
}
fn label_value(label: &str, value: String) -> AnyElement {
    let tone = value.clone();
    view()
        .flex_row()
        .gap_3()
        .py_2()
        .child(
            text(label.to_owned())
                .text_sm()
                .text_color(move || theme().muted_foreground)
                .flex_1(),
        )
        .child(
            text(value)
                .text_color(move || ui::money_tone(&tone))
                .text_sm()
                .tabular_nums()
                .text_right(),
        )
        .into_element()
}
fn link(title: &str, subtitle: &str, value: String, id: &str, path: String) -> AnyElement {
    fui::row(title.into(), subtitle.into(), value, id.into(), move || {
        fui::navigate(path.clone())
    })
}

pub fn render(path: String) -> AnyElement {
    let parts: Vec<_> = path.trim_matches('/').split('/').collect();
    match parts.as_slice() {
        ["wealth"] => overview(),
        ["wealth", "assets"] => asset_list(),
        ["wealth", "assets", "new"] => asset_editor(None),
        ["wealth", "assets", id, "edit"] => asset_editor(Some((*id).into())),
        ["wealth", "assets", id, "price"] => price_editor((*id).into()),
        ["wealth", "assets", id, "record"] => operation_editor(None, Some((*id).into())),
        ["wealth", "assets", id, "record", kind] => {
            operation_editor_kind(None, Some((*id).into()), operation_kind(kind).ok())
        }
        ["wealth", "assets", id] => asset_detail((*id).into()),
        ["wealth", "operations", "new"] => operation_editor(None, None),
        ["wealth", "operations", id, "edit"] => operation_editor(Some((*id).into()), None),
        ["wealth", "operations", id] => operation_detail((*id).into()),
        ["wealth", "fx"] => fx_editor(),
        _ => fui::page(
            "财富",
            view()
                .gap_3()
                .child(note("这个财富页面不存在，请返回财富总览。"))
                .child(fui::action("财富总览", "wealth-home", || {
                    fui::navigate("/wealth")
                })),
        ),
    }
}

#[path = "wealth/overview.rs"]
mod overview;
use overview::*;
#[path = "wealth/assets.rs"]
mod assets;
use assets::*;
#[path = "wealth/editors.rs"]
mod editors;
use editors::*;
#[path = "wealth/operations.rs"]
mod operations;
use operations::*;
#[cfg(test)]
#[path = "wealth/tests.rs"]
mod draft_tests;

#[path = "wealth/summary.rs"]
mod summary;
