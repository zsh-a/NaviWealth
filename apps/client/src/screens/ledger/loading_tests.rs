use super::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
#[component]
fn FactsProbe() -> impl IntoElement {
    let month = signal(0);
    let version = signal(0);
    let calls = signal(0);
    let query = signal(0);
    let kind = signal(0);
    let category = signal(0);
    let limit = signal(50);
    let record_error = signal(String::new());
    effect(move || {
        query.get();
        kind.get();
        category.get();
        limit.get();
        record_error.set(String::new());
    });
    let facts = observe_month(month, version, move |month| {
        calls.update(|v| *v += 1);
        Box::pin(async move {
            MonthData {
                composition: if month == 0 {
                    Ok(vec![composition::Composition {
                        currency: "CNY".into(),
                        categories: vec![("旧月餐饮".into(), 10.into())],
                        total: 10.into(),
                    }])
                } else {
                    Err("离线".into())
                },
                totals: Ok(vec![("CNY".into(), 0.into(), 10.into())]),
                budgets: Ok(vec![]),
            }
        })
    });
    view()
        .child(composition::render(facts.composition))
        .child(text(move || facts.composition_error.get()))
        .child(text(move || format!("请求 {}", calls.get())))
        .child(text(move || record_error.get()))
        .child(ui::secondary_button(
            "切月",
            move || month.set(1),
            "month",
            None,
        ))
        .child(ui::secondary_button(
            "搜索",
            move || query.update(|v| *v += 1),
            "query",
            None,
        ))
        .child(ui::secondary_button(
            "类型",
            move || kind.update(|v| *v += 1),
            "kind",
            None,
        ))
        .child(ui::secondary_button(
            "分类",
            move || category.update(|v| *v += 1),
            "category",
            None,
        ))
        .child(ui::secondary_button(
            "更多",
            move || limit.update(|v| *v += 50),
            "limit",
            None,
        ))
        .child(ui::secondary_button(
            "刷新",
            move || version.update(|v| *v += 1),
            "refresh",
            None,
        ))
}
#[test]
fn composition_failure_survives_successful_record_refresh() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<FactsProbe>())).unwrap();
    app.wait_for("text:旧月餐饮 100%").unwrap();
    app.press("id:month").unwrap();
    app.wait_for("text:分类构成暂不可用：离线").unwrap();
    assert_eq!(
        app.screen()
            .count("id:ledger-category-composition")
            .unwrap(),
        0
    );
    app.press("id:query").unwrap();
    app.wait_for("text:分类构成暂不可用：离线").unwrap();
    assert_eq!(
        app.screen()
            .count("id:ledger-category-composition")
            .unwrap(),
        0
    );
}
#[test]
fn month_facts_ignore_record_filters_and_pagination() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<FactsProbe>())).unwrap();
    app.wait_for("text:请求 1").unwrap();
    for id in ["query", "kind", "category", "limit"] {
        app.press(&format!("id:{id}")).unwrap();
    }
    app.wait_for("text:请求 1").unwrap();
    app.press("id:month").unwrap();
    app.wait_for("text:请求 2").unwrap();
    app.press("id:refresh").unwrap();
    app.wait_for("text:请求 3").unwrap();
}
