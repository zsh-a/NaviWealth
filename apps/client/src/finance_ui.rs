//! Finance workspace primitives. Business values stay exact; animation is presentation only.
use crate::{state::Services, ui};
use nsh_base::PickedDate;
use nsh_base::{DatePickerValue, SheetEvent, date_picker, theme};
use nsh_core::prelude::*;
use rust_decimal::{Decimal, prelude::ToPrimitive};
use std::{collections::BTreeMap, future::Future, pin::Pin, rc::Rc, sync::Arc};

#[derive(Clone, Copy)]
pub(crate) struct Navigation(pub Signal<Vec<String>>);
#[derive(Clone, Copy)]
pub(crate) struct Feedback(pub Signal<String>);
#[derive(Clone, Copy)]
pub(crate) struct ChangedFact(pub Signal<Option<(String, String)>>);

/// Keep the receipt beside the financial facts it changed, until the next task.
pub fn acknowledge(path: impl Into<String>, message: impl Into<String>) {
    if let Some(fact) = use_context::<ChangedFact>() {
        fact.0.set(Some((path.into(), message.into())));
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
    view()
        .child(when(
            move || fact.is_some_and(|f| f.0.get().is_some_and(|(p, _)| p == path)),
            move || {
                let opacity = animated_value(0.75);
                if !reduce_motion() {
                    opacity.timing(0.0, 1800.0, Easing::Bezier(0.16, 1.0, 0.3, 1.0));
                }
                view()
                    .absolute()
                    .inset_0()
                    .rounded(px(12.0))
                    .bg(move || theme().secondary)
                    .pointer_events(PointerEvents::None)
                    .bind_opacity(&opacity)
            },
        ))
        .child(body)
        .child(dynamic(move || match fact.and_then(|f| f.0.get()) {
            Some((path, message)) if path == receipt_path => text(message)
                .test_id("finance-changed-fact")
                .text_xs()
                .text_color(move || theme().primary)
                .into_element(),
            _ => view().into_element(),
        }))
        .into_element()
}
#[derive(Clone, Copy)]
pub(crate) struct LeaveGuard(pub Signal<Option<GuardCallback>>);
#[derive(Clone)]
pub(crate) struct GuardCallback {
    pub check: Rc<dyn Fn() -> bool>,
}
impl PartialEq for GuardCallback {
    fn eq(&self, other: &Self) -> bool {
        Rc::ptr_eq(&self.check, &other.check)
    }
}
fn request_back() {
    if let Some(guard) = use_context::<LeaveGuard>()
        && guard.0.get().is_some_and(|check| (check.check)())
    {
        return;
    }
    back();
}
fn notice_default(message: &str) {
    if use_context::<Feedback>().is_some_and(|f| f.0.get().is_empty()) {
        notice(message);
    }
}

pub fn services() -> Arc<Services> {
    use_context::<Arc<Services>>().expect("services")
}
pub fn navigate(path: impl Into<String>) {
    let path = path.into();
    clear_acknowledgement();
    dismiss_keyboard();
    if let Some(nav) = use_context::<Navigation>() {
        if let Some(index) = root_tab(&path)
            && let Some(tab) = use_context::<crate::ShellTab>()
        {
            tab.0.set(index);
            nav.0.set(Vec::new());
            return;
        }
        nav.0.update(|routes| {
            if let Some(index) = routes.iter().position(|route| route == &path) {
                routes.truncate(index + 1);
            } else {
                routes.push(path);
            }
        });
    }
}
fn root_tab(path: &str) -> Option<u8> {
    match path {
        "/today" => Some(0),
        "/activity" => Some(1),
        "/wealth" => Some(2),
        "/plan" => Some(3),
        _ => None,
    }
}
pub(crate) fn dismiss_route(path: &str) {
    if let Some(nav) = use_context::<Navigation>() {
        nav.0.update(|routes| {
            if routes.last().is_some_and(|current| current == path) {
                routes.pop();
            }
        });
    }
}
pub fn back() {
    dismiss_keyboard();
    if let Some(nav) = use_context::<Navigation>() {
        nav.0.update(|routes| {
            routes.pop();
        });
    }
}
pub fn refresh() {
    if let Some(v) = use_context::<crate::state::DataVersion>() {
        v.0.update(|v| *v += 1);
    }
}
pub fn notice(message: impl Into<String>) {
    if let Some(f) = use_context::<Feedback>() {
        f.0.set(message.into());
    }
}
pub fn feedback_overlay(bottom: f32) -> AnyElement {
    view()
        .absolute()
        .left_4()
        .right_4()
        .bottom(move || px(safe_area().bottom.0 + bottom))
        .child(feedback())
        .into_element()
}
fn feedback() -> AnyElement {
    let message = use_context::<Feedback>()
        .map(|v| v.0)
        .unwrap_or_else(|| signal(String::new()));
    when(
        move || !message.get().is_empty(),
        move || {
            let offset = animated_value(0.0);
            if !reduce_motion() {
                offset.set(6.0);
                offset.timing(0.0, 180.0, Easing::Bezier(0.16, 1.0, 0.3, 1.0));
            }
            view()
                .flex_row()
                .items_center()
                .px_4()
                .py_2()
                .gap_2()
                .rounded(px(12.0))
                .bg(move || theme().primary)
                .bind_translate_y(&offset)
                .test_id("finance-feedback")
                .child(
                    text(move || message.get())
                        .text_sm()
                        .text_color(move || theme().primary_foreground)
                        .flex_1(),
                )
                .child(
                    view()
                        .role(AccessibilityRole::Button)
                        .label("收起反馈")
                        .test_id("finance-notice-dismiss")
                        .w(px(48.0))
                        .h(px(48.0))
                        .items_center()
                        .justify_center()
                        .on_press(move || message.set(String::new()))
                        .child(
                            ui::icon(ui::Icon::Close)
                                .text_color(move || theme().primary_foreground),
                        ),
                )
        },
    )
    .into_element()
}
pub fn finish(target: Option<String>, pop: bool) {
    let nav = use_context::<Navigation>();
    let version = use_context::<crate::state::DataVersion>();
    let root = target
        .as_deref()
        .and_then(root_tab)
        .zip(use_context::<crate::ShellTab>());
    if let Some((index, tab)) = root {
        tab.0.set(index);
    }
    if let Some(version) = version {
        version.0.update(|v| *v += 1);
    }
    if let Some(nav) = nav {
        nav.0.update(|routes| {
            if root.is_some() {
                routes.clear();
                return;
            }
            if pop {
                routes.pop();
            }
            if let Some(path) = target {
                if let Some(index) = routes.iter().position(|route| route == &path) {
                    routes.truncate(index + 1);
                } else {
                    routes.push(path);
                }
            }
        });
    }
}
fn friendly_error(error: String) -> String {
    error
        .strip_prefix("invalid data: ")
        .unwrap_or(&error)
        .to_owned()
}

pub fn page(title: impl Into<String>, body: impl IntoElement) -> AnyElement {
    let title = title.into();
    let nav = use_context::<Navigation>();
    view()
        .flex_1()
        .bg(move || theme().background)
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .px_4()
                .min_h(px(52.0))
                .child(when(
                    move || nav.is_some_and(|v| !v.0.get().is_empty()),
                    || {
                        view()
                            .role(AccessibilityRole::Button)
                            .label("返回")
                            .test_id("finance-back")
                            .w(px(48.0))
                            .h(px(48.0))
                            .items_center()
                            .justify_center()
                            .on_press(request_back)
                            .child(ui::icon(ui::Icon::Back))
                    },
                ))
                .child(
                    text(title)
                        .text_size(px(21.0))
                        .font_weight(FontWeight::SEMIBOLD)
                        .flex_1(),
                ),
        )
        .child(
            ui::interactive_scroll().flex_1().child(
                view()
                    .px_4()
                    .pt_2()
                    .pb_safe_area_plus(px(96.0))
                    .gap_4()
                    .child(body),
            ),
        )
        .child(feedback_overlay(16.0))
        .into_element()
}
pub fn section(title: impl Into<String>, body: impl IntoElement) -> AnyElement {
    view()
        .gap_2()
        .pt_3()
        .child(
            text(title.into())
                .text_size(px(15.0))
                .font_weight(FontWeight::SEMIBOLD),
        )
        .child(body)
        .into_element()
}
pub fn row(
    title: String,
    subtitle: String,
    trailing: String,
    id: String,
    on_press: impl Fn() + 'static,
) -> AnyElement {
    let has_subtitle = !subtitle.is_empty();
    view()
        .role(AccessibilityRole::Button)
        .label(format!("{title}，{subtitle}，{trailing}"))
        .test_id(&id)
        .on_press(on_press)
        .min_h(px(62.0))
        .py_3()
        .flex_row()
        .items_center()
        .gap_3()
        .border_b_1()
        .border_color(move || theme().border)
        .active(|s| s.opacity(0.7))
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(
                    text(title)
                        .text_size(px(15.0))
                        .font_weight(FontWeight::MEDIUM),
                )
                .child(when(
                    move || has_subtitle,
                    move || {
                        text(subtitle.clone())
                            .text_size(px(12.0))
                            .text_color(move || theme().muted_foreground)
                    },
                )),
        )
        .child(
            text(trailing)
                .text_size(px(14.0))
                .tabular_nums()
                .flex_shrink_0()
                .max_w(move || px((window().width.0 - 32.0) * 0.52))
                .text_right(),
        )
        .child(
            ui::icon(ui::Icon::Arrow)
                .w(px(16.0))
                .h(px(16.0))
                .text_color(move || theme().muted_foreground),
        )
        .into_element()
}
pub fn metric(label: String, value: String, caption: String) -> AnyElement {
    view()
        .gap_2()
        .py_3()
        .child(
            text(label)
                .text_size(px(14.0))
                .text_color(move || theme().muted_foreground),
        )
        .child(
            text(value)
                .text_size(px(29.0))
                .font_weight(FontWeight::SEMIBOLD)
                .tabular_nums(),
        )
        .child(
            text(caption)
                .text_size(px(12.0))
                .text_color(move || theme().muted_foreground),
        )
        .into_element()
}
pub fn action(
    label: impl Into<String>,
    id: &'static str,
    on_press: impl Fn() + 'static,
) -> AnyElement {
    view()
        .role(AccessibilityRole::Button)
        .test_id(id)
        .on_press(on_press)
        .min_h(px(48.0))
        .px_3()
        .justify_center()
        .rounded(px(8.0))
        .active(|s| {
            s.opacity(0.65)
                .scale(if reduce_motion() { 1.0 } else { 0.98 })
        })
        .transition_transform()
        .duration(if reduce_motion() { 0.0 } else { 100.0 })
        .ease_out()
        .child(
            text(label.into())
                .text_size(px(14.0))
                .font_weight(FontWeight::MEDIUM)
                .text_color(move || theme().primary),
        )
        .into_element()
}

/// Gaps are explicit missing evidence, never interpolated into a complete net worth.
pub fn line_chart(points: Vec<(String, Option<Decimal>)>, label: String) -> AnyElement {
    let values: Vec<f64> = points
        .iter()
        .filter_map(|(_, v)| v.and_then(|v| v.to_f64()))
        .collect();
    if values.len() < 2 {
        let summary = points
            .iter()
            .rev()
            .find_map(|(d, v)| v.map(|v| format!("{d} · {}", ui::money(v))));
        return view()
            .gap_1()
            .child(text(label).text_sm().font_weight(FontWeight::MEDIUM))
            .child(
                text(summary.unwrap_or_else(|| "等待完整估值依据".into()))
                    .text_sm()
                    .tabular_nums(),
            )
            .child(
                text("累计两个完整记录时点后显示曲线；缺失时点不连线。")
                    .text_xs()
                    .text_color(move || theme().muted_foreground),
            )
            .into_element();
    }
    let low = values.iter().copied().fold(f64::INFINITY, f64::min);
    let high = values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let spread = (high - low).max(0.000001);
    let denominator = points.len().saturating_sub(1).max(1) as f64;
    let mut paths = String::new();
    let mut dots = String::new();
    let mut active = false;
    for (i, (_, value)) in points.iter().enumerate() {
        if let Some(v) = value.and_then(|v| v.to_f64()) {
            let x = 8.0 + i as f64 / denominator * 304.0;
            let y = 96.0 - (v - low) / spread * 80.0;
            dots.push_str(&format!(
                "<circle cx='{x:.2}' cy='{y:.2}' r='3' fill='currentColor'/>"
            ));
            paths.push_str(&format!(
                "{} {x:.2} {y:.2} ",
                if active { "L" } else { "M" }
            ));
            active = true;
        } else {
            active = false;
        }
    }
    let svg_src = format!(
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 320 112'><path d='M8 104H312' stroke='currentColor' opacity='.18'/><path d='{paths}' stroke='currentColor' stroke-width='2.2' fill='none' stroke-linecap='round' stroke-linejoin='round'/>{dots}</svg>"
    );
    let first = points.first().map(|v| v.0.clone()).unwrap_or_default();
    let last = points.last().map(|v| v.0.clone()).unwrap_or_default();
    let summary = points
        .iter()
        .rev()
        .find_map(|(d, v)| v.map(|v| format!("{d} · {}", ui::money(v))))
        .unwrap_or_else(|| "等待完整估值依据".into());
    view()
        .gap_2()
        .child(
            text(label)
                .text_size(px(15.0))
                .font_weight(FontWeight::MEDIUM),
        )
        .child(
            svg(nsh_core::element::ImageSrc::svg_markup(&svg_src))
                .h(px(112.0))
                .w_full()
                .text_color(move || theme().primary),
        )
        .child(
            view()
                .flex_row()
                .justify_between()
                .child(text(first).text_xs())
                .child(text(last).text_xs())
                .text_color(move || theme().muted_foreground),
        )
        .child(text(summary).text_sm().tabular_nums())
        .child(when(
            move || points.iter().any(|(_, v)| v.is_none()),
            || {
                text("曲线中断处缺少当时的价格或汇率")
                    .text_xs()
                    .text_color(move || theme().muted_foreground)
            },
        ))
        .into_element()
}

#[derive(Clone)]
enum FieldKind {
    Text,
    Decimal,
    Date,
    Choice(Vec<(String, String)>),
    Multiline,
}
#[derive(Clone)]
pub struct Field {
    pub value: Signal<String>,
    id: &'static str,
    label: &'static str,
    initial: String,
    kind: FieldKind,
    help: Option<&'static str>,
    visible: Option<Rc<dyn Fn() -> bool>>,
}
impl Field {
    pub fn text(id: &'static str, label: &'static str, initial: impl Into<String>) -> Self {
        let initial = initial.into();
        Self {
            value: signal(initial.clone()),
            id,
            label,
            initial,
            kind: FieldKind::Text,
            help: None,
            visible: None,
        }
    }
    pub fn decimal(id: &'static str, label: &'static str, initial: impl Into<String>) -> Self {
        Self {
            kind: FieldKind::Decimal,
            ..Self::text(id, label, initial)
        }
    }
    pub fn date(id: &'static str, label: &'static str, initial: impl Into<String>) -> Self {
        Self {
            kind: FieldKind::Date,
            ..Self::text(id, label, initial)
        }
    }
    pub fn multiline(id: &'static str, label: &'static str, initial: impl Into<String>) -> Self {
        Self {
            kind: FieldKind::Multiline,
            ..Self::text(id, label, initial)
        }
    }
    pub fn choice(
        id: &'static str,
        label: &'static str,
        initial: impl Into<String>,
        options: Vec<(String, String)>,
    ) -> Self {
        Self {
            kind: FieldKind::Choice(options),
            ..Self::text(id, label, initial)
        }
    }
    pub fn help(mut self, text: &'static str) -> Self {
        self.help = Some(text);
        self
    }
    pub fn show_when(mut self, predicate: impl Fn() -> bool + 'static) -> Self {
        self.visible = Some(Rc::new(predicate));
        self
    }
    fn render(self) -> AnyElement {
        let value = self.value;
        let id = self.id;
        let label = self.label;
        let input = match self.kind {
            FieldKind::Choice(options) => {
                ui::select_field(label, signal(options), value, id).into_element()
            }
            FieldKind::Date => date_field(label, id, value),
            kind => ui::labeled(
                label,
                ui::themed_input()
                    .label(label)
                    .value(value)
                    .on_change(move |v: &str| value.set(v.to_owned()))
                    .test_id(id)
                    .multiline(matches!(kind, FieldKind::Multiline))
                    .keyboard_type(if matches!(kind, FieldKind::Decimal) {
                        KeyboardType::Numeric
                    } else {
                        KeyboardType::Default
                    })
                    .min_h(px(if matches!(kind, FieldKind::Multiline) {
                        112.0
                    } else {
                        48.0
                    }))
                    .px_3()
                    .py_2()
                    .rounded(px(10.0))
                    .bg(move || theme().card)
                    .border_1()
                    .border_color(move || theme().border)
                    .text_size(px(15.0)),
            )
            .into_element(),
        };
        let mut result = view().gap_1().child(input);
        if let Some(help) = self.help {
            result = result.child(
                text(help)
                    .text_xs()
                    .text_color(move || theme().muted_foreground),
            );
        }
        if let Some(visible) = self.visible {
            result
                .style_when(move || !visible(), |s| s.hidden())
                .into_element()
        } else {
            result.into_element()
        }
    }
}
pub fn date_field(label: &'static str, id: &'static str, value: Signal<String>) -> AnyElement {
    use nsh_base::{CalendarEntry, CalendarItemKind};
    view()
        .gap_1()
        .child(
            text(label)
                .text_sm()
                .text_color(move || theme().muted_foreground),
        )
        .child(
            date_picker()
                .value(move || {
                    DatePickerValue::Controlled(
                        chrono::NaiveDate::parse_from_str(&value.get(), "%Y-%m-%d")
                            .ok()
                            .map(Into::into)
                            .unwrap_or_default(),
                    )
                })
                .on_change(move |e: &PickedDate| {
                    if let Some(date) = e.value.start() {
                        value.set(date.format("%Y-%m-%d").to_string());
                    }
                })
                .accessibility_label(label)
                .date_format("%Y年%m月%d日")
                .first_day_of_week(1_u32)
                .previous_accessibility_label("上个月")
                .next_accessibility_label("下个月")
                .backdrop_style(|s| s.bg(hsla(0.0, 0.0, 0.0, 0.32)))
                .popup_style(|s| {
                    s.bg(move || theme().card)
                        .px_2()
                        .py_4()
                        .pb_safe_area_plus(px(20.0))
                        .rounded_t(px(16.0))
                })
                .calendar_style(|s| s.w_full().gap_2())
                .header_style(|s| s.min_h(px(48.0)).items_center().gap_1())
                .row_style(|s| s.gap_0())
                .item_style(|s| {
                    s.min_h(px(48.0))
                        .min_w(px(48.0))
                        .px_1()
                        .items_center()
                        .justify_center()
                        .rounded(px(8.0))
                        .text_size(px(15.0))
                        .text_color(move || theme().foreground)
                        .selected(|s| {
                            s.bg(move || theme().primary)
                                .text_color(move || theme().primary_foreground)
                        })
                })
                .render_item(|entry: &CalendarEntry| -> AnyElement {
                    match entry.kind {
                        CalendarItemKind::Previous => ui::icon(ui::Icon::Back).into_element(),
                        CalendarItemKind::Next => ui::icon(ui::Icon::Arrow).into_element(),
                        CalendarItemKind::Weekday => text(
                            ["日", "一", "二", "三", "四", "五", "六"]
                                [entry.value.clamp(0, 6) as usize],
                        )
                        .text_sm()
                        .into_element(),
                        CalendarItemKind::MonthToggle | CalendarItemKind::Month => {
                            text(format!("{}月", entry.value)).text_sm().into_element()
                        }
                        _ => text(entry.value.to_string())
                            .text_sm()
                            .tabular_nums()
                            .opacity(if entry.outside { 0.45 } else { 1.0 })
                            .into_element(),
                    }
                })
                .trigger(ui::state_button(
                    move || value.get(),
                    dismiss_keyboard,
                    id,
                    false,
                )),
        )
        .into_element()
}
pub type Values = BTreeMap<&'static str, String>;
pub type SaveFuture = Pin<Box<dyn Future<Output = Result<Option<String>, String>>>>;
pub fn value(values: &Values, id: &str) -> String {
    values.get(id).cloned().unwrap_or_default()
}
pub fn required(values: &Values, id: &str, label: &str) -> Result<String, String> {
    let v = value(values, id).trim().to_owned();
    if v.is_empty() {
        Err(format!("请填写{label}"))
    } else {
        Ok(v)
    }
}
pub fn decimal(values: &Values, id: &str, label: &str) -> Result<Decimal, String> {
    required(values, id, label)?
        .parse()
        .map_err(|_| format!("{label}请输入有效数字"))
}
pub fn date(values: &Values, id: &str, label: &str) -> Result<i64, String> {
    ui::date_to_secs(&required(values, id, label)?).ok_or_else(|| format!("{label}请选择有效日期"))
}

pub fn form(
    title: impl Into<String>,
    fields: Vec<Field>,
    submit: impl Fn(Values) -> SaveFuture + 'static,
) -> AnyElement {
    let saving = signal(false);
    let error = signal(String::new());
    let discard = signal(false);
    let fields = Rc::new(fields);
    let guard = fields.clone();
    let submit_fields = fields.clone();
    let submit = Rc::new(submit);
    let check = move || {
        if saving.get() {
            return true;
        }
        if guard.iter().any(|f| f.value.get() != f.initial) {
            discard.set(true);
            true
        } else {
            false
        }
    };
    if let Some(scope) = use_context::<LeaveGuard>() {
        scope.0.set(Some(GuardCallback {
            check: Rc::new(check),
        }));
    } else {
        on_back_press(check);
    }
    let cancel_fields = fields.clone();
    let cancel = move || {
        if saving.get() {
            return;
        }
        if cancel_fields.iter().any(|f| f.value.get() != f.initial) {
            discard.set(true);
        } else {
            back();
        }
    };
    page(
        title,
        view()
            .gap_4()
            .children(fields.iter().cloned().map(Field::render))
            .child(ui::error_line(error))
            .child(ui::primary_button(
                "保存",
                move || {
                    if saving.get() {
                        return;
                    }
                    saving.set(true);
                    error.set(String::new());
                    notice("");
                    dismiss_keyboard();
                    let values = submit_fields
                        .iter()
                        .map(|f| (f.id, f.value.get()))
                        .collect();
                    let task = submit(values);
                    spawn(async move {
                        let result = task.await;
                        saving.set(false);
                        match result {
                            Ok(target) => {
                                notice_default("已保存");
                                finish(target, true);
                            }
                            Err(e) => error.set(friendly_error(e)),
                        }
                    });
                },
                "finance-form-save",
                Some(saving),
            ))
            .child(ui::secondary_button(
                "取消",
                cancel,
                "finance-form-cancel",
                Some(saving),
            ))
            .child(
                ui::app_sheet()
                    .open(move || Some(discard.get()))
                    .on_open_change(move |e: &SheetEvent| {
                        if let SheetEvent::OpenChange(v, _) = e {
                            discard.set(*v);
                        }
                    })
                    .child(
                        view()
                            .p_5()
                            .pb_safe_area_plus(px(20.0))
                            .gap_3()
                            .bg(move || theme().background)
                            .child(
                                text("放弃未保存的修改？")
                                    .text_lg()
                                    .font_weight(FontWeight::SEMIBOLD),
                            )
                            .child(ui::primary_button(
                                "继续填写",
                                move || discard.set(false),
                                "finance-form-keep",
                                None,
                            ))
                            .child(
                                view()
                                    .role(AccessibilityRole::Button)
                                    .label("放弃修改")
                                    .test_id("finance-form-discard")
                                    .min_h(px(48.0))
                                    .items_center()
                                    .justify_center()
                                    .on_press(move || {
                                        discard.set(false);
                                        back();
                                    })
                                    .child(
                                        text("放弃修改")
                                            .text_sm()
                                            .text_color(move || theme().destructive),
                                    ),
                            ),
                    ),
            ),
    )
}

pub fn confirm(
    title: String,
    message: String,
    confirm_label: String,
    id: &'static str,
    submit: impl Fn() -> SaveFuture + 'static,
) -> AnyElement {
    let open = signal(false);
    let busy = signal(false);
    let error = signal(String::new());
    let submit = Rc::new(submit);
    let trigger_label = confirm_label.clone();
    view()
        .child(ui::secondary_button(
            trigger_label,
            move || {
                error.set(String::new());
                open.set(true);
            },
            id,
            None,
        ))
        .child(
            ui::app_sheet()
                .open(move || Some(open.get()))
                .on_open_change(move |e: &SheetEvent| {
                    if !busy.get()
                        && let SheetEvent::OpenChange(v, _) = e
                    {
                        open.set(*v);
                    }
                })
                .child(
                    view()
                        .p_5()
                        .pb_safe_area_plus(px(20.0))
                        .gap_3()
                        .bg(move || theme().background)
                        .child(text(title).text_lg().font_weight(FontWeight::SEMIBOLD))
                        .child(
                            text(message)
                                .text_sm()
                                .text_color(move || theme().muted_foreground),
                        )
                        .child(ui::error_line(error))
                        .child(ui::danger_button(
                            confirm_label,
                            move || {
                                if busy.get() {
                                    return;
                                }
                                busy.set(true);
                                let task = submit();
                                spawn(async move {
                                    let result = task.await;
                                    busy.set(false);
                                    match result {
                                        Ok(target) => {
                                            open.set(false);
                                            notice("操作已完成");
                                            let pop = target.is_some();
                                            finish(target, pop);
                                        }
                                        Err(e) => error.set(friendly_error(e)),
                                    }
                                });
                            },
                            "finance-confirm-submit",
                            busy,
                        ))
                        .child(ui::secondary_button(
                            "取消",
                            move || open.set(false),
                            "finance-confirm-cancel",
                            Some(busy),
                        )),
                ),
        )
        .into_element()
}
