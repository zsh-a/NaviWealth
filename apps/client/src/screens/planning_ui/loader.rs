//! Retain mounted read views while a new snapshot is pending or unavailable.
use super::*;
use std::{pin::Pin, rc::Rc, sync::Arc};

pub(super) type LoadFuture<T> = Pin<Box<dyn Future<Output = Result<T, String>>>>;
pub(super) fn load<T: Clone + PartialEq + 'static>(
    title: &'static str,
    fetch: impl Fn(Arc<Services>) -> LoadFuture<T> + 'static,
    draw: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    load_mode(title, false, fetch, draw)
}
/// Entry snapshot is frozen for the form lifetime, including external writes.
pub(super) fn load_form<T: Clone + PartialEq + 'static>(
    title: &'static str,
    fetch: impl Fn(Arc<Services>) -> LoadFuture<T> + 'static,
    draw: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    load_mode(title, true, fetch, draw)
}
pub(super) fn load_mode<T: Clone + PartialEq + 'static>(
    title: &'static str,
    freeze_draft: bool,
    fetch: impl Fn(Arc<Services>) -> LoadFuture<T> + 'static,
    draw: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    let data: Signal<Option<T>> = signal(None);
    let error = signal(String::new());
    let loading = signal(true);
    let retry = signal(0_u64);
    let generation = Rc::new(std::cell::Cell::new(0_u64));
    let version = use_context::<crate::state::DataVersion>()
        .expect("data version")
        .0;
    let services = fui::services();
    effect(move || {
        if !freeze_draft {
            version.get();
        }
        retry.get();
        let n = generation.get() + 1;
        generation.set(n);
        let generation = generation.clone();
        let future = fetch(services.clone());
        loading.set(true);
        spawn(async move {
            let result = future.await;
            if generation.get() != n {
                return;
            }
            match result {
                Ok(value) => {
                    if untracked(|| data.get()).as_ref() != Some(&value) {
                        if untracked(|| data.get()).is_some() {
                            ui::animate_list_change();
                        }
                        data.set(Some(value));
                    }
                    error.set(String::new());
                }
                Err(e) => error.set(e),
            }
            loading.set(false);
        });
    });
    view()
        .flex_1()
        .child(dynamic(move || {
            // This branch deliberately never reads loading/error. Pending, failed
            // and identical refreshes therefore cannot dispose the content owner.
            if let Some(value) = data.get() {
                return untracked(|| draw(value));
            }
            if loading.get() {
                return fui::page(title, ui::skeleton());
            }
            fui::page(
                title,
                view()
                    .gap_3()
                    .child(text(move || error.get()).text_color(move || theme().destructive))
                    .child(fui::action("重新读取", "plan-load-retry", move || {
                        retry.update(|n| *n += 1)
                    })),
            )
        }))
        .child(when(
            move || data.get().is_some() && !error.get().is_empty(),
            move || {
                view()
                    .absolute()
                    .bottom(px(16.0))
                    .left(px(18.0))
                    .right(px(18.0))
                    .p_3()
                    .bg(move || theme().card)
                    .rounded(move || px(ui::card_radius()))
                    .child(
                        text(move || format!("刷新未完成，保留上次资料：{}", error.get()))
                            .text_color(move || theme().destructive),
                    )
                    .child(fui::action("重新读取", "plan-load-retry", move || {
                        retry.update(|n| *n += 1)
                    }))
            },
        ))
        .into_element()
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    use std::cell::Cell;

    #[component]
    fn RefreshProbe() -> impl IntoElement {
        provide_context(Services::shared());
        let version = signal(0_u64);
        provide_context(crate::state::DataVersion(version));
        let calls = Rc::new(Cell::new(0));
        let draws = Rc::new(Cell::new(0));
        view()
            .flex_1()
            .child(fui::action("刷新", "refresh-probe", move || {
                version.update(|v| *v += 1)
            }))
            .child(load(
                "读取探针",
                move |_| {
                    let n = calls.get();
                    calls.set(n + 1);
                    Box::pin(async move {
                        match n {
                            1 => std::future::pending().await,
                            2 => Err("离线探针".into()),
                            4 => Ok(2),
                            _ => Ok(1),
                        }
                    })
                },
                move |n| {
                    draws.set(draws.get() + 1);
                    let draft = signal(String::new());
                    fui::page(
                        "读取探针",
                        view()
                            .child(text(format!("已读取 {n}")))
                            .child(text(format!("绘制次数 {}", draws.get())))
                            .child(text(move || draft.get()))
                            .child(ui::text_field("上下文", "", draft, "refresh-draft")),
                    )
                },
            ))
    }

    #[test]
    fn refresh_keeps_content_on_pending_failure_and_unchanged_retry() {
        crate::enable_test_mode();
        let mut app = Headless::start(EngineConfig::new(Root::of::<RefreshProbe>())).unwrap();
        let nodes = std::sync::Arc::new(std::sync::Mutex::new(std::collections::BTreeSet::new()));
        let capture = nodes.clone();
        app.observe(move |_, batch| {
            for item in &batch.items {
                match item {
                    nsh_core::MountItem::Create {
                        id,
                        kind: nsh_core::ViewKind::Input | nsh_core::ViewKind::Scroll,
                    } => {
                        capture.lock().unwrap().insert(*id);
                    }
                    nsh_core::MountItem::Delete { id } => {
                        capture.lock().unwrap().remove(id);
                    }
                    _ => {}
                }
            }
        });
        app.wait_for("text:已读取 1").unwrap();
        app.type_text("id:refresh-draft", "保留焦点内容").unwrap();
        let mounted = nodes.lock().unwrap().clone();
        assert!(
            !mounted.is_empty(),
            "track the native input and scroll nodes"
        );
        for _ in 0..2 {
            app.press("id:refresh-probe").unwrap();
            assert!(app.shows("已读取 1"));
            assert!(app.shows("保留焦点内容"));
            assert!(app.shows("绘制次数 1"));
            assert_eq!(*nodes.lock().unwrap(), mounted);
            assert!(!app.shows("正在读取本地财务资料…"));
        }
        app.wait_for("id:plan-load-retry").unwrap();
        app.press("id:plan-load-retry").unwrap();
        assert!(app.shows("保留焦点内容"));
        assert!(app.shows("绘制次数 1"));
        app.wait_for_gone("id:plan-load-retry", std::time::Duration::from_secs(3))
            .unwrap();
        app.press("id:refresh-probe").unwrap();
        app.wait_for("text:已读取 2").unwrap();
        assert_eq!(
            *nodes.lock().unwrap(),
            mounted,
            "refresh must reconcile native input and scroll nodes"
        );
    }
}
