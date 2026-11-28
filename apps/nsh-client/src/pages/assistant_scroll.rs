//! Navigate to a specific record even when it predates the visible message window.
use crate::data::assistant;
use nsh_core::prelude::*;
use std::time::Duration;

#[derive(Clone, Copy)]
pub(super) struct ThreadScroll {
    pub list: ElementRef,
    pub offset: Signal<f32>,
    pub following: Signal<bool>,
    pub highlighted: Signal<Option<String>>,
}

impl ThreadScroll {
    pub fn new() -> Self {
        Self {
            list: element_ref(),
            offset: signal(0.0),
            following: signal(true),
            highlighted: signal(None),
        }
    }

    pub fn latest(self) {
        if let Some(id) = assistant::capture_focus() {
            assistant::clear_capture_focus(&id);
        }
        self.highlighted.set(None);
        self.following.set(true);
        self.list.scroll_to_end(false);
    }

    pub fn reveal(self, row: ElementRef, id: String) {
        set_timeout(Duration::from_millis(40), move || {
            if assistant::capture_focus().as_deref() != Some(&id) {
                return;
            }
            spawn(async move {
                let (Some(target), Some(viewport)) =
                    (row.measure().await, self.list.measure().await)
                else {
                    return;
                };
                if assistant::capture_focus().as_deref() != Some(&id) {
                    return;
                }
                let y = (self.offset.get_untracked() + target.page.y.0 - viewport.page.y.0 - 12.0)
                    .max(0.0);
                self.following.set(false);
                self.list.scroll_to(
                    Point {
                        x: px(0.0),
                        y: px(y),
                    },
                    false,
                );
                self.highlighted.set(Some(id.clone()));
                assistant::clear_capture_focus(&id);
                set_timeout(Duration::from_millis(1800), move || {
                    if self.highlighted.get_untracked().as_deref() == Some(&id) {
                        self.highlighted.set(None);
                    }
                });
            });
        });
    }
}
