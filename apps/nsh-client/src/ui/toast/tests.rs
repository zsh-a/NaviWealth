use super::*;
use nsh_core::{Command, time::Clock};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;

#[component]
fn Probe() -> impl IntoElement {
    let undone = signal(0);
    let viewed = signal(0);
    let behind = signal(0);
    let sheet = signal(false);
    let control = |label: &'static str, run: Rc<dyn Fn()>| {
        button()
            .min_h(px(44.0))
            .on_press(move || run())
            .child(text(label))
    };
    view()
        .w_full()
        .h_full()
        .child(control(
            "Save",
            Rc::new(move || {
                show_capture_receipt(
                    "Saved",
                    ("Undo".into(), Rc::new(move || undone.update(|n| *n += 1))),
                    ("View".into(), Rc::new(move || viewed.update(|n| *n += 1))),
                );
            }),
        ))
        .child(control("Notice", Rc::new(|| show_toast("Copied", None))))
        .child(control(
            "Retry notice",
            Rc::new(move || {
                show_toast(
                    "Failed",
                    Some((
                        "Retry".into(),
                        Rc::new(move || {
                            undone.update(|n| *n += 1);
                            show_toast("Retried", None);
                        }),
                    )),
                )
            }),
        ))
        .child(control(
            "Open task",
            Rc::new(move || {
                clear_notice();
                sheet.set(true);
            }),
        ))
        .child(control("Close task", Rc::new(move || sheet.set(false))))
        .child(text(move || format!("Undo count {}", undone.get())))
        .child(text(move || format!("View count {}", viewed.get())))
        .child(text(move || format!("Behind count {}", behind.get())))
        .child(
            button()
                .accessibility_label("Under toast")
                .absolute()
                .bottom_0()
                .left_0()
                .right_0()
                .h(px(120.0))
                .on_press(move || behind.update(|n| *n += 1))
                .child(text("Underlying control")),
        )
        .child(
            view()
                .absolute()
                .inset_0()
                .pointer_events(PointerEvents::BoxNone)
                .style_when(move || sheet.get(), |s| s.hidden())
                .child(toast_host(|| 24.0)),
        )
        .child(when(
            move || sheet.get(),
            || {
                view()
                    .absolute()
                    .inset_0()
                    .pointer_events(PointerEvents::BoxNone)
                    .child(toast_view(|| 24.0))
            },
        ))
}

fn start(reduced: bool) -> Headless {
    let mut config = EngineConfig::new(Root::of::<Probe>());
    config.clock = Clock::manual(std::time::SystemTime::UNIX_EPOCH);
    let mut app = Headless::start(config).unwrap();
    app.set_environment("motion preference", move |e| e.reduce_motion = reduced)
        .unwrap();
    app.wait_for("Save").unwrap();
    app
}

fn announced(app: &Headless) -> Vec<&str> {
    app.screen()
        .commands()
        .iter()
        .filter_map(|(_, c)| match c {
            Command::Announce(text) => Some(text.as_str()),
            _ => None,
        })
        .collect()
}

#[test]
fn new_messages_replace_actions_and_actions_can_show_their_own_message() -> Result<(), String> {
    let mut app = start(false);
    app.press("Save")?;
    app.press("Notice")?;
    assert!(!app.shows("Saved"));
    assert!(!app.shows("Undo"));
    app.press("Open task")?;
    assert!(!app.shows("Copied"));
    app.press("Retry notice")?;
    app.press("Retry")?;
    app.wait_for("Retried")?;
    assert!(app.shows("Undo count 1"));
    assert!(!app.shows("Retry"));
    app.press("Close task")?;
    assert!(app.shows("Retried"));
    assert!(app.shows("Undo count 1"));
    Ok(())
}

#[test]
fn a_new_task_retires_view_but_undo_runs_once_across_mirrored_surfaces() -> Result<(), String> {
    let mut app = start(false);
    app.press("Save")?;
    app.press("Open task")?;
    assert!(app.shows("Undo"));
    assert!(!app.shows("View"));
    assert_eq!(announced(&app), ["Saved"]);
    app.press("Undo")?;
    app.press("Close task")?;
    assert!(!app.shows("Undo"));
    assert!(!app.shows("Saved"));
    assert!(app.shows("Undo count 1"));
    assert!(app.shows("View count 0"));
    Ok(())
}

#[test]
fn changing_surfaces_does_not_restart_the_four_and_a_half_second_lifetime() -> Result<(), String> {
    for reduced in [false, true] {
        let mut app = start(reduced);
        app.press("Save")?;
        app.run_for(Duration::from_millis(2000))?;
        app.press("Open task")?;
        app.run_for(Duration::from_millis(2000))?;
        assert!(app.shows("Undo"));
        app.press("Close task")?;
        app.run_for(Duration::from_millis(499))?;
        assert!(app.shows("Undo"));
        app.run_for(Duration::from_millis(1))?;
        if reduced {
            assert!(!app.shows("Undo"), "reduced motion has no exit delay");
        } else {
            app.run_for(EXIT_FOR)?;
            assert!(!app.shows("Undo"));
        }
        assert_eq!(announced(&app), ["Saved"]);
        assert!(app.shows("Undo count 0"));
    }
    Ok(())
}

#[test]
fn suspension_does_not_extend_undo_and_replacement_has_its_own_deadline() -> Result<(), String> {
    let mut app = start(false);
    app.press("Save")?;
    app.fast_forward(Duration::from_secs(10))?;
    assert!(!app.shows("Undo"));
    app.press("Save")?;
    app.run_for(Duration::from_secs(4))?;
    app.press("Notice")?;
    app.run_for(Duration::from_secs(1))?;
    assert!(app.shows("Copied"));
    app.fast_forward(Duration::from_secs(4))?;
    assert!(!app.shows("Copied"));
    Ok(())
}

#[test]
fn stack_leaves_controls_outside_the_bubble_tappable() -> Result<(), String> {
    let mut app = start(false);
    app.press("Save")?;
    app.press_at("label:Under toast", point(px(4.0), px(60.0)))?;
    assert!(app.shows("Behind count 1"));
    assert!(app.shows("Undo"));
    app.press("View")?;
    assert!(app.shows("View count 1"));
    assert!(!app.shows("Undo"));
    Ok(())
}
