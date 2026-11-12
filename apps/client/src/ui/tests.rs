use super::*;
#[test]
fn dates_reject_impossible_days() {
    assert!(date_to_secs("2026-02-29").is_none());
    assert!(date_to_secs("2026-04-31").is_none());
    assert_eq!(ymd(date_to_secs("2024-02-29").unwrap()), "2024-02-29");
}
#[test]
fn amounts_keep_small_values_exact() {
    assert_eq!(money("0.000001".parse().unwrap()), "0.000001");
    assert_eq!(money("42.5".parse().unwrap()), "42.50");
}

#[component]
fn KeyboardTapProbe() -> impl IntoElement {
    let open = signal(false);
    let value = signal(String::new());
    let kind = signal("支出".to_owned());
    view()
        .child(primary_button(
            "打开",
            move || {
                kind.set("支出".to_owned());
                open.set(true);
            },
            "tap-open",
            None,
        ))
        .child(when(
            move || open.get(),
            move || {
                nsh_base::dialog()
                    .on_cancel(move || open.set(false))
                    .child(
                        interactive_scroll()
                            .flex_1()
                            .test_id("tap-scroll")
                            .child(
                                input()
                                    .value(value)
                                    .on_change(move |v: &str| value.set(v.to_owned()))
                                    .test_id("tap-input"),
                            )
                            .child(choice_button(
                                "收入",
                                move || kind.get() == "收入",
                                move || kind.set("收入".to_owned()),
                                "tap-income",
                            ))
                            .child(choice_button(
                                "转账",
                                move || kind.get() == "转账",
                                move || kind.set("转账".to_owned()),
                                "tap-transfer",
                            ))
                            .child(text(move || format!("当前类型：{}", kind.get()))),
                    )
                    .child(secondary_button(
                        "关闭",
                        move || open.set(false),
                        "tap-close",
                        None,
                    ))
            },
        ))
}

#[test]
fn interactive_scroll_keeps_handled_taps_with_focused_input_across_reopens() {
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    use std::sync::{Arc, Mutex};
    let observed = Arc::new(Mutex::new(Vec::new()));
    let capture = observed.clone();
    let mut app = Headless::start(EngineConfig::new(Root::of::<KeyboardTapProbe>())).unwrap();
    app.observe(move |_, batch| {
        for item in &batch.items {
            if let nsh_core::MountItem::ScrollBehavior { behavior, .. } = item {
                capture.lock().unwrap().push(behavior.keyboard_taps);
            }
        }
    });
    app.wait_for("id:tap-open").unwrap();
    for _ in 0..4 {
        app.press("id:tap-open").unwrap();
        app.type_text("id:tap-input", "1").unwrap();
        app.press("id:tap-income").unwrap();
        app.wait_for("text:当前类型：收入").unwrap();
        app.press("id:tap-transfer").unwrap();
        app.wait_for("text:当前类型：转账").unwrap();
        app.press("id:tap-close").unwrap();
    }
    let taps = observed.lock().unwrap();
    assert!(
        taps.len() >= 4,
        "each newly mounted native scroll receives its tap policy"
    );
    assert!(taps.iter().all(|taps| *taps == KeyboardTaps::Handled));
}
