use super::*;

/// Keep the receipt beside the financial facts it changed, until the next task.
pub fn acknowledge(path: impl Into<String>, message: impl Into<String>) {
    acknowledge_fact(path, message, None);
}
pub fn acknowledge_fact(
    path: impl Into<String>,
    message: impl Into<String>,
    record_id: Option<String>,
) {
    if let Some(fact) = use_context::<ChangedFact>() {
        fact.0.set(Some(Fact {
            path: path.into(),
            message: message.into(),
            record_id,
        }));
    }
}
pub fn clear_acknowledgement() {
    if let Some(fact) = use_context::<ChangedFact>() {
        fact.0.set(None);
    }
}
pub fn changed_fact(path: String, body: impl IntoElement) -> AnyElement {
    let fact = use_context::<ChangedFact>();
    let receipt_path = path.clone();
    let probe_path = path.clone();
    view()
        .child(when(
            move || fact.is_some_and(|f| f.0.get().is_some_and(|p| p.path == probe_path)),
            move || {
                let opacity = animated_value(0.75);
                if !reduce_motion() {
                    opacity.timing(0.0, 1800.0, Easing::Bezier(0.16, 1.0, 0.3, 1.0));
                }
                view()
                    .absolute()
                    .inset_0()
                    .rounded(move || px(theme().number("radius").unwrap_or(10.0)))
                    .bg(wash)
                    .pointer_events(PointerEvents::None)
                    .bind_opacity(&opacity)
            },
        ))
        .child(body)
        .child(dynamic(move || match fact.and_then(|f| f.0.get()) {
            Some(fact) if fact.path == receipt_path => text(fact.message)
                .test_id("finance-changed-fact")
                .text_size(move || px(crate::ui::token("type-caption")))
                .text_color(move || theme().muted_foreground)
                .into_element(),
            _ => view().into_element(),
        }))
        .into_element()
}

/// A quiet wash that lights a row up when the acknowledged change touched it.
pub fn record_highlight(record_id: &str) -> AnyElement {
    let id = record_id.to_owned();
    let test_id = format!("record-highlight-{id}");
    let fact = use_context::<ChangedFact>();
    view()
        .absolute()
        .inset_0()
        .pointer_events(PointerEvents::None)
        .child(when(
            move || {
                fact.is_some_and(|f| {
                    f.0.get()
                        .is_some_and(|p| p.record_id.as_deref() == Some(id.as_str()))
                })
            },
            move || {
                let opacity = animated_value(0.75);
                if !reduce_motion() {
                    opacity.timing(0.0, 1800.0, Easing::Bezier(0.16, 1.0, 0.3, 1.0));
                }
                view()
                    .test_id(&test_id)
                    .absolute()
                    .inset_0()
                    .rounded(move || px(ui::row_radius()))
                    .bg(wash)
                    .pointer_events(PointerEvents::None)
                    .bind_opacity(&opacity)
            },
        ))
        .into_element()
}

/// What the undo button does to the offered record.
#[derive(Clone, Copy, PartialEq)]
pub enum UndoAction {
    /// A deletion being undone: bring the record back.
    Restore,
    /// A just-created record being undone: remove it again.
    Remove,
}

#[derive(Clone, PartialEq)]
pub struct UndoPending {
    pub record_id: String,
    pub message: String,
    pub action: UndoAction,
    pub expires_at: i64,
}

pub const UNDO_WINDOW_MS: u64 = 60_000;

#[derive(Clone, Copy)]
pub(crate) struct UndoOffer {
    pub pending: Signal<Option<UndoPending>>,
    pub busy: Signal<bool>,
    pub error: Signal<String>,
}

/// Offer the 60-second cross-page undo for one record change. A later offer
/// replaces the previous one, and the window survives navigation.
pub fn offer_undo(record_id: String, message: impl Into<String>, action: UndoAction) {
    if let Some(offer) = use_context::<UndoOffer>() {
        let expires_at = lifeos::ids::now_millis() + UNDO_WINDOW_MS as i64;
        offer.error.set(String::new());
        offer.pending.set(Some(UndoPending {
            record_id,
            message: message.into(),
            action,
            expires_at,
        }));
        let pending = offer.pending;
        set_timeout(
            std::time::Duration::from_millis(UNDO_WINDOW_MS),
            move || {
                pending.update(|p| {
                    if p.as_ref().is_some_and(|p| p.expires_at <= expires_at) {
                        *p = None;
                    }
                });
            },
        );
    }
}

/// The global undo pill: mounted once in the shell, visible on every tab and
/// route so the window is genuinely cross-page.
pub fn undo_pill(bottom: f32) -> AnyElement {
    let offer = use_context::<UndoOffer>().expect("undo offer");
    let pending = offer.pending;
    let busy = offer.busy;
    let error = offer.error;
    let version = use_context::<crate::state::DataVersion>();
    let now = signal(lifeos::ids::now_millis());
    let _timer = set_interval(std::time::Duration::from_secs(1), move || {
        now.set(lifeos::ids::now_millis())
    });
    let press = move || {
        if busy.get() {
            return;
        }
        let Some(p) = pending.get_untracked() else {
            return;
        };
        if lifeos::ids::now_millis() >= p.expires_at {
            pending.set(None);
            return;
        }
        busy.set(true);
        error.set(String::new());
        let s = services();
        spawn(async move {
            let result = match p.action {
                UndoAction::Restore => s.restore_finance_record(&p.record_id).await,
                UndoAction::Remove => s.delete_finance_record(&p.record_id).await,
            };
            busy.set(false);
            match result {
                Ok(()) => {
                    pending.update(|current| {
                        if current.as_ref() == Some(&p) {
                            *current = None;
                        }
                    });
                    if let Some(v) = version {
                        v.0.update(|v| *v += 1);
                    }
                    notice(match p.action {
                        UndoAction::Restore => "已恢复这笔记录；余额与预算已更新。",
                        UndoAction::Remove => "已撤销这笔记录；余额与预算已更新。",
                    });
                }
                Err(e) => {
                    if pending.get_untracked().as_ref() == Some(&p) {
                        error.set(friendly_error(e));
                    }
                }
            }
        });
    };
    view()
        .absolute()
        .left_4()
        .right_4()
        .bottom(move || px(safe_area().bottom.0 + bottom))
        .child(when(
            move || pending.get().is_some(),
            move || {
                let offset = animated_value(0.0);
                if !reduce_motion() {
                    offset.set(6.0);
                    offset.spring(0.0, ui::settle_spring());
                }
                view()
                    .gap_1()
                    .rounded(move || px(theme().number("radius").unwrap_or(10.0)))
                    .bg(move || theme().primary)
                    .px_4()
                    .py_2()
                    .bind_translate_y(&offset)
                    .test_id("finance-undo-offer")
                    .child(
                        view()
                            .flex_row()
                            .items_center()
                            .gap_2()
                            .child(
                                text(move || {
                                    pending
                                        .get()
                                        .map(|p| {
                                            format!(
                                                "{} · {}秒",
                                                p.message,
                                                ((p.expires_at - now.get()).max(0) + 999) / 1000
                                            )
                                        })
                                        .unwrap_or_default()
                                })
                                .text_size(move || px(crate::ui::token("type-section")))
                                .text_color(move || theme().primary_foreground)
                                .flex_1(),
                            )
                            .child(
                                ui::press_target(press)
                                    .label("撤销")
                                    .test_id("finance-undo-action")
                                    .min_h(px(48.0))
                                    .min_w(px(48.0))
                                    .items_center()
                                    .justify_center()
                                    .disabled(move || busy.get())
                                    .child(
                                        text("撤销")
                                            .text_size(move || px(crate::ui::token("type-section")))
                                            .font_weight(FontWeight::MEDIUM)
                                            .text_color(move || theme().primary_foreground),
                                    ),
                            ),
                    )
                    .child(when(
                        move || !error.get().is_empty(),
                        move || {
                            text(move || error.get())
                                .text_size(move || px(crate::ui::token("type-caption")))
                                .text_color(move || theme().primary_foreground)
                        },
                    ))
                    .into_element()
            },
        ))
        .into_element()
}
