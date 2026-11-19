use super::*;

pub(super) fn action_row(
    label: impl Fn() -> &'static str + Copy + 'static,
    note: impl Fn() -> &'static str + Copy + 'static,
    glyph: Icon,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    row_button(press)
        .px(px(space::CARD))
        .rounded(px(radius::FIELD))
        .min_h(px(64.0))
        .gap_3()
        .child(
            view()
                .w(px(32.0))
                .h(px(32.0))
                .rounded_full()
                .bg(color::INK)
                .items_center()
                .justify_center()
                .child(icon(glyph, 18.0, color::ON_ACTION)),
        )
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(text(label).typo(Type::Headline).text_color(color::INK))
                .child(text(note).typo(Type::Subhead).text_color(color::MUTED)),
        )
        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
}

/// A data entry: a quiet glyph, its name and a scope note.
pub(super) fn nav_row(
    label: impl Fn() -> &'static str + Copy + 'static,
    note: impl Fn() -> &'static str + Copy + 'static,
    glyph: Icon,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    row_button(press)
        .px(px(space::CARD))
        .rounded(px(radius::FIELD))
        .min_h(px(52.0))
        .gap_3()
        .child(icon(glyph, 20.0, color::MUTED))
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(text(label).typo(Type::Headline).text_color(color::INK))
                .child(text(note).typo(Type::Subhead).text_color(color::MUTED)),
        )
        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
}

pub(super) fn account_group(
    kind: AccountKind,
    accounts: &[Account],
    balances: &std::collections::BTreeMap<Account, i64>,
    checks: &[navi_finance::repository::BalanceCheck],
) -> Option<AnyElement> {
    let own: Vec<_> = accounts.iter().filter(|a| a.kind() == kind).collect();
    if own.is_empty() {
        return None;
    }
    Some(
        view()
            .gap_1()
            .child(
                text(if kind == AccountKind::Assets {
                    s().cash_accounts
                } else {
                    s().debt_accounts
                })
                .typo(Type::Subhead)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(color::MUTED)
                .role(AccessibilityRole::Header),
            )
            .children(own.into_iter().map(|a| {
                let balance = balances.get(a).copied().unwrap_or(0);
                let checked = checks
                    .iter()
                    .filter(|c| c.account == *a)
                    .max_by_key(|c| c.checked_at);
                let detail = checked
                    .map(|c| format!("{} · {}", s().account_checked, s().short_date(Day(c.day))))
                    .unwrap_or_else(|| s().account_unchecked.into());
                let name = crate::ui::currency::account_label(a);
                let route = a.to_string();
                let value = assets::displayed(a, balance);
                let label = format!(
                    "{name}, {}, {detail}",
                    crate::ui::currency::format(value, a.currency())
                );
                view().child(
                    row_button(move || nav::push(Route::Account(route.clone())))
                        .accessibility_label(move || Some(label.clone().into()))
                        .px_0()
                        .py_3()
                        .min_h(px(56.0))
                        .gap_3()
                        .child(icon(
                            if kind == AccountKind::Assets {
                                Icon::Wallet
                            } else {
                                Icon::CreditCard
                            },
                            22.0,
                            color::MUTED,
                        ))
                        .child(
                            view()
                                .flex_1()
                                .min_w(px(0.0))
                                .flex_row()
                                .items_center()
                                .gap_3()
                                .style_when(
                                    || font_scale() > 1.2 || window().width.0 < 350.0,
                                    |s| s.flex_col().items_start().gap_1(),
                                )
                                .child(
                                    view()
                                        .flex_1()
                                        .min_w(px(0.0))
                                        .gap_1()
                                        .style_when(
                                            || font_scale() > 1.2 || window().width.0 < 350.0,
                                            |s| s.w_full(),
                                        )
                                        .child(
                                            text(name)
                                                .typo(Type::Headline)
                                                .text_color(color::INK)
                                                .number_of_lines(1),
                                        )
                                        .child(
                                            text(detail)
                                                .typo(Type::Caption)
                                                .text_color(color::MUTED),
                                        ),
                                )
                                .child(
                                    view().min_w(px(0.0)).flex_shrink(1.0_f32).child(amount_in(
                                        value,
                                        Type::Headline,
                                        a.currency(),
                                    )),
                                ),
                        )
                        .child(icon(Icon::ChevronRight, 16.0, color::MUTED)),
                )
            }))
            .into_element(),
    )
}

pub(super) fn total(label: &'static str, value: i64) -> impl IntoElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap_1()
        .child(text(label).typo(Type::Caption).text_color(color::MUTED))
        .child(amount(value, Type::Body))
}

pub(super) fn net_figure(value: i64) -> impl IntoElement {
    let written = display_money(value);
    let (whole, fraction) = written.split_once('.').expect("money decimals");
    view()
        .flex_row()
        .items_baseline()
        .flex_wrap()
        .min_w(px(0.0))
        .accessible(true)
        .label(move || crate::ui::currency::format(value, navi_finance::currency::Currency::CNY))
        .child(
            text(if value < 0 { "−¥" } else { "¥" })
                .typo(Type::Figure)
                .text_color(color::MUTED)
                .mr_1(),
        )
        .child(
            text(whole.trim_start_matches('-').to_owned())
                .typo(Type::Display)
                .min_w(px(0.0))
                .flex_shrink(1.0_f32)
                .number_of_lines(1)
                .shrink_to_fit(0.35)
                .tabular_nums()
                .text_color(color::INK),
        )
        .child(
            text(format!(".{fraction}"))
                .typo(Type::Title)
                .tabular_nums()
                .text_color(color::MUTED),
        )
}

pub(super) fn cost_details(items: Vec<(String, String)>) -> impl IntoElement {
    let expanded = signal(false);
    let count = items.len();
    view()
        .child(
            row_button(move || expanded.update(|v| *v = !*v))
                .px_0()
                .min_h(px(48.0))
                .child(
                    text(move || s().cost_holdings(count))
                        .typo(Type::Subhead)
                        .text_color(color::BODY),
                )
                .child(dynamic(move || {
                    icon(
                        if expanded.get() {
                            Icon::ChevronDown
                        } else {
                            Icon::ChevronRight
                        },
                        16.0,
                        color::MUTED,
                    )
                    .into_element()
                })),
        )
        .child(when(
            move || expanded.get(),
            move || {
                view()
                    .test_id("cost-holdings")
                    .children(items.iter().cloned().map(|(id, name)| {
                        row_button(move || nav::push(Route::Holding(id.clone())))
                            .child(text(name).typo(Type::Body).text_color(color::INK))
                    }))
            },
        ))
}

pub(super) fn quote_refresh_row() -> impl IntoElement {
    when(
        || {
            let book = finance::holdings_snapshot();
            let bindings = crate::data::catalog::bindings();
            finance::accounts()
                .iter()
                .any(|a| a.is_cash() && a.currency() != navi_finance::currency::Currency::CNY)
                || book.securities.iter().any(|sec| {
                    (sec.currency() != navi_finance::currency::Currency::CNY
                        || bindings.iter().any(|b| b.security == sec.id))
                        && book
                            .position(sec, clock::today().0)
                            .is_ok_and(|p| p.quantity > 0)
                })
        },
        || {
            let expanded = signal(false);
            view()
                .gap_1()
                .child(
                    view()
                        .flex_row()
                        .items_center()
                        .style_when(
                            || font_scale() > 1.2 || window().width.0 < 350.0,
                            |s| s.flex_col().items_start(),
                        )
                        .gap_3()
                        .child(dynamic(move || {
                            let status = crate::data::market::status();
                            let summary = if let Some(at) = status.completed_at {
                                let ms = at.as_millisecond();
                                let time = format!(
                                    "{} {}",
                                    s().short_date(crate::domain::meal::Day(
                                        clock::zoned(ms).date()
                                    )),
                                    clock::time_label(ms)
                                );
                                s().refresh_summary(&time, status.updated, status.failed)
                            } else {
                                crate::i18n::catalog::copy("Prices and FX", "价格与汇率").to_owned()
                            };
                            let caption =
                                text(summary).typo(Type::Caption).text_color(color::MUTED);
                            if status.failed_items.is_empty() {
                                caption.flex_1().into_element()
                            } else {
                                row_button(move || expanded.update(|open| *open = !*open))
                                    .px_0()
                                    .min_h(px(48.0))
                                    .flex_1()
                                    .child(caption)
                                    .child(icon(
                                        if expanded.get() {
                                            Icon::ChevronDown
                                        } else {
                                            Icon::ChevronRight
                                        },
                                        16.0,
                                        color::MUTED,
                                    ))
                                    .into_element()
                            }
                        }))
                        .child(
                            Btn::ghost()
                                .size(crate::ui::Size::Small)
                                .label(|| {
                                    if crate::data::market::status().refreshing {
                                        s().refreshing_quotes()
                                    } else {
                                        s().refresh_quotes()
                                    }
                                    .into()
                                })
                                .disabled(|| crate::data::market::status().refreshing)
                                .on_press(move || {
                                    expanded.set(false);
                                    crate::data::tasks::spawn_app(crate::data::market::refresh(
                                        true,
                                    ))
                                }),
                        ),
                )
                .child(when(
                    move || {
                        expanded.get() && !crate::data::market::status().failed_items.is_empty()
                    },
                    || {
                        text(|| crate::data::market::status().failed_items.join(" · "))
                            .typo(Type::Caption)
                            .text_color(color::BODY)
                    },
                ))
        },
    )
}
