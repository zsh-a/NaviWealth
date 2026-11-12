use super::*;

#[derive(Clone, Copy)]
pub(super) enum BackupCommand {
    Export,
    ChooseImport,
    Restore,
}

pub(super) fn provider_picker(selected: Signal<String>) -> impl IntoElement {
    let options: [&'static str; 2] = ["anthropic", "openai"];
    view().flex_row().gap_2().children(
        options
            .iter()
            .map(|&option| {
                ui::chip(
                    option.to_owned(),
                    move || selected.get() == option,
                    move || selected.set(option.to_owned()),
                )
            })
            .collect::<Vec<_>>(),
    )
}

/// One opt-in domain: label + reactive enable/disable button. The switch
/// updates the shared signal immediately (tabs follow at once) and
/// persists to the settings KV, mirroring onto `Services` so sync and the
/// AI tools pick it up.
pub(super) fn domain_toggle_row(
    spec: &'static domains::DomainSpec,
    domains: DomainsState,
    services: Arc<Services>,
) -> impl IntoElement {
    let is_on = move || domains.is_enabled(spec.key);
    view()
        .flex_row()
        .items_center()
        .gap_3()
        .child(
            view()
                .flex_1()
                .child(text(spec.label).text_base().font_weight(FontWeight::MEDIUM)),
        )
        .child(
            ui::NativeControl(
                nsh_base::switch()
                    .checked(is_on)
                    .accessibility_label(spec.label)
                    .track_style(|s| {
                        s.w(px(40.0))
                            .h(px(24.0))
                            .rounded_full()
                            .bg(move || theme().muted)
                    })
                    .thumb_class("checked:translate-x-4")
                    .thumb_style(|s| {
                        s.size(px(20.0))
                            .m(px(2.0))
                            .rounded_full()
                            .bg(move || theme().primary)
                            .shadow_sm()
                            .transition_transform()
                            .duration(if nsh_core::prelude::reduce_motion() {
                                0.0
                            } else {
                                180.0
                            })
                    })
                    .min_w(px(44.0))
                    .min_h(px(44.0))
                    .items_center()
                    .justify_center()
                    .on_change(move |next: &bool| {
                        let next = *next;
                        domains.0.update(|list| {
                            if next {
                                if !list.contains(&spec.key) {
                                    list.push(spec.key);
                                }
                            } else {
                                list.retain(|key| *key != spec.key);
                            }
                        });
                        let services = services.clone();
                        spawn(async move {
                            domains::set_enabled(&services, spec, next).await;
                        });
                    }),
            )
            .test_id(spec.toggle_test_id),
        )
}

pub(super) fn reactive_text(signal: Signal<String>) -> impl IntoElement {
    text(move || signal.get())
}
