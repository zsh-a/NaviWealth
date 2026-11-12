//! Thin root-attribute adapter for the official Button. No input behavior is reimplemented.
use super::*;
use nsh_core::element::ElNode;
pub struct NativeControl<E>(pub E);
pub type NativeButton = NativeControl<nsh_base::ButtonElement>;
pub type NativeToggle = NativeControl<nsh_base::ToggleElement>;
impl<E: IntoElement> IntoElement for NativeControl<E> {
    fn into_element(self) -> AnyElement {
        self.0.into_element()
    }
}
impl<E: Element> Element for NativeControl<E> {
    fn node(&mut self) -> &mut ElNode {
        self.0.node()
    }
}
impl<E: ParentElement> ParentElement for NativeControl<E> {}
// NSH 0.5 component builders expose style but not these primitive root attributes.
// Delegate them through NSH's own traits to preserve existing test IDs and labels.
impl<E: Element> Accessible for NativeControl<E> {}
impl<E: Element> Interactive for NativeControl<E> {}
impl NativeButton {
    pub fn disabled(mut self, value: impl Fn() -> bool + 'static) -> Self {
        self.0 = self.0.disabled(value);
        self
    }
}
impl NativeToggle {
    pub fn disabled(mut self, value: impl Fn() -> bool + 'static) -> Self {
        self.0 = self.0.disabled(value);
        self
    }
}

/// A branded Switch; state and interaction are owned by nsh-base.
pub fn switch_field(label: impl Into<String>, checked: Signal<bool>, id: &str) -> impl Element {
    let label = label.into();
    NativeControl(
        nsh_base::switch()
            .checked(checked)
            .accessibility_label(label.clone())
            .on_change(move |v: &bool| checked.set(*v))
            .min_h(px(44.0))
            .flex_row()
            .items_center()
            .gap_3()
            .track_style(|s| {
                s.w(px(40.0))
                    .h(px(24.0))
                    .rounded_full()
                    .bg(move || theme().muted)
            })
            .track_class("checked:bg-primary")
            .thumb_class("checked:translate-x-4 checked:bg-primary-foreground")
            .thumb_style(|s| {
                s.size(px(20.0))
                    .m(px(2.0))
                    .rounded_full()
                    .bg(move || theme().primary)
                    .shadow_sm()
                    .transition_transform()
                    .duration(if reduce_motion() { 0.0 } else { 180.0 })
            })
            .child(text(label).text_base()),
    )
    .test_id(id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    #[component]
    fn Buttons() -> impl IntoElement {
        let blocked = signal(true);
        let count = signal(0);
        view()
            .child(primary_button(
                "提交",
                move || count.update(|n| *n += 1),
                "commit",
                Some(blocked),
            ))
            .child(secondary_button(
                "启用",
                move || blocked.set(false),
                "enable",
                None,
            ))
            .child(text(move || format!("调用 {}", count.get())))
    }
    #[test]
    fn official_button_keeps_disabled_gating_and_existing_test_ids() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<Buttons>())).unwrap();
        app.wait_for("id:commit").unwrap();
        assert!(
            app.screen()
                .accessibility_state("id:commit")
                .unwrap()
                .disabled
        );
        assert!(app.press("id:commit").is_err());
        app.press("id:enable").unwrap();
        app.press("id:commit").unwrap();
        app.wait_for("text:调用 1").unwrap();
    }
}
