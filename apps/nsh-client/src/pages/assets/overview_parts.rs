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
                asset_row(
                    name,
                    crate::ui::currency::format(value, a.currency()),
                    detail,
                    checked.is_none(),
                    if kind == AccountKind::Assets {
                        Icon::Wallet
                    } else {
                        Icon::CreditCard
                    },
                    move || nav::push(Route::Account(route.clone())),
                )
            }))
            .into_element(),
    )
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
