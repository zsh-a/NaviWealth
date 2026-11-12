//! Motion never interpolates monetary facts, and always honors reduced motion.
use super::*;
use nsh_core::{LayoutAnimation, LayoutCurve, LayoutTransition};

pub fn animate_list_change() {
    if !reduce_motion() {
        animate_layout(LayoutAnimation::all(LayoutTransition::new(
            LayoutCurve::EaseOut,
            token("motion-layout-ms"),
        )));
    }
}

/// A quiet settle when a choice becomes selected. Nothing animates on mount.
pub fn selection_scale(selected: impl Fn() -> bool + 'static) -> AnimatedValue {
    let value = animated_value(1.0);
    let mut_previous = std::rc::Rc::new(std::cell::Cell::new(None));
    effect(move || {
        let next = selected();
        let previous = mut_previous.replace(Some(next));
        if previous.is_some_and(|old| old != next) && next && !reduce_motion() {
            value.set(0.985);
            value.spring(1.0, settle_spring());
        } else if reduce_motion() {
            value.set(1.0);
        }
    });
    value
}

pub fn settle_spring() -> Spring {
    Spring {
        stiffness: token("spring-stiffness"),
        damping: token("spring-damping"),
        mass: token("spring-mass"),
        velocity: None,
        ..Default::default()
    }
}
pub fn enter_offset() -> AnimatedValue {
    let offset = animated_value(0.0);
    if !reduce_motion() {
        offset.set(token("motion-enter"));
        offset.spring(0.0, settle_spring());
    }
    offset
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    #[component]
    fn MotionProbe() -> impl IntoElement {
        let selected = signal(false);
        choice_button(
            "选择",
            move || selected.get(),
            move || {
                animate_list_change();
                selected.set(true);
            },
            "motion-choice",
        )
    }
    #[test]
    fn reduced_motion_keeps_selection_and_skips_layout_animation() {
        for reduced in [false, true] {
            let mut app = Headless::start(EngineConfig::new(Root::of::<MotionProbe>())).unwrap();
            app.wait_for("id:motion-choice").unwrap();
            app.set_environment("减少动态效果", |e| e.reduce_motion = reduced)
                .unwrap();
            let observed = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
            let capture = observed.clone();
            app.observe(move |_, batch| {
                if batch
                    .items
                    .iter()
                    .any(|item| matches!(item, nsh_core::MountItem::LayoutAnimation(_)))
                {
                    capture.store(true, std::sync::atomic::Ordering::SeqCst);
                }
            });
            app.press("id:motion-choice").unwrap();
            assert!(
                app.screen()
                    .accessibility_state("id:motion-choice")
                    .unwrap()
                    .pressed
                    == Some(nsh_core::Checked::True)
            );
            let animated = observed.load(std::sync::atomic::Ordering::SeqCst);
            assert_eq!(animated, !reduced);
        }
    }
}
