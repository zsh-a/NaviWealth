use super::*;

#[derive(Clone)]
enum FieldKind {
    Text,
    Decimal,
    Money,
    QuantityOrMoney(Rc<dyn Fn() -> Option<String>>),
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
    currency: Option<Rc<dyn Fn() -> String>>,
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
            currency: None,
        }
    }
    pub fn decimal(id: &'static str, label: &'static str, initial: impl Into<String>) -> Self {
        Self {
            kind: FieldKind::Decimal,
            ..Self::text(id, label, initial)
        }
    }
    pub fn money(id: &'static str, label: &'static str, initial: impl Into<String>) -> Self {
        Self {
            kind: FieldKind::Money,
            ..Self::text(id, label, ui::raw_decimal_input(&initial.into()))
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
    pub fn currency(mut self, currency: impl Fn() -> String + 'static) -> Self {
        self.currency = Some(Rc::new(currency));
        self
    }
    pub fn quantity_or_money(mut self, currency: impl Fn() -> Option<String> + 'static) -> Self {
        self.kind = FieldKind::QuantityOrMoney(Rc::new(currency));
        self
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
        let own_currency = self.currency;
        let input = match self.kind {
            FieldKind::Choice(options) => ui::select_field(
                label,
                signal(options.into_iter().map(ui::SelectOption::from).collect()),
                value,
                id,
            )
            .into_element(),
            FieldKind::Date => date_field(label, id, value),
            kind => ui::labeled(
                label,
                match kind {
                    FieldKind::QuantityOrMoney(ref currency) => {
                        let currency = currency.clone();
                        ui::money_input_when(value, move || currency())
                    }
                    FieldKind::Money => {
                        let currency = use_context::<ui::MoneyCurrency>();
                        ui::money_input(value, move || {
                            own_currency
                                .as_ref()
                                .map(|c| c())
                                .unwrap_or_else(|| currency.map(|c| c.0.get()).unwrap_or_default())
                        })
                    }
                    _ => ui::themed_input()
                        .value(value)
                        .on_change(move |v: &str| value.set(v.to_owned())),
                }
                .label(label)
                .test_id(id)
                .multiline(matches!(kind, FieldKind::Multiline))
                .keyboard_type(
                    if matches!(
                        kind,
                        FieldKind::Decimal | FieldKind::Money | FieldKind::QuantityOrMoney(_)
                    ) {
                        KeyboardType::Numeric
                    } else {
                        KeyboardType::Default
                    },
                )
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
                .text_size(move || px(crate::ui::token("type-body"))),
            )
            .into_element(),
        };
        let mut result = view().gap_1().child(input);
        if let Some(help) = self.help {
            result = result.child(
                text(help)
                    .text_size(move || px(crate::ui::token("type-caption")))
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
    let currency = signal(String::new());
    let currency_fields = fields.clone();
    effect(move || {
        let explicit = currency_fields.iter().find(|f| f.id.ends_with("currency"));
        let code = explicit.map(|f| f.value.get()).unwrap_or_default();
        currency.set(code);
    });
    provide_context(ui::MoneyCurrency(currency));
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
                            .child(ui::text_button(
                                "放弃修改",
                                "finance-form-discard",
                                move || {
                                    discard.set(false);
                                    back();
                                },
                                true,
                            )),
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
                                .text_size(move || px(crate::ui::token("type-section")))
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
