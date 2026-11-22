use super::*;

pub(super) fn manage_row(
    label: fn() -> &'static str,
    note: Option<fn() -> &'static str>,
    count: Option<usize>,
    glyph: Icon,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    row_button(press)
        .px_1()
        .py_2()
        .min_h(px(60.0))
        .gap_3()
        .child(icon(glyph, 22.0, color::MUTED))
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(text(label).typo(Type::Headline).text_color(color::INK))
                .child(note.map(|note| text(note).typo(Type::Subhead).text_color(color::MUTED))),
        )
        .child(count.map(|n| {
            text(n.to_string())
                .typo(Type::Body)
                .tabular_nums()
                .text_color(color::MUTED)
        }))
        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
}

/// The name still opens the account when the owner wants to rename it or see its history.
fn new_account_row(account: &Account, glyph: Icon) -> AnyElement {
    let name = crate::ui::currency::account_label(account);
    let detail = account.to_string();
    let check = detail.clone();
    let spoken_action = format!("{name}, {}", opening_action());
    let stack = || font_scale() > 1.2 || window().width.0 < 350.0;
    view()
        .min_h(px(64.0))
        .flex_row()
        .items_center()
        .gap_x(px(12.0))
        .style_when(stack, |s| s.flex_col().items_start())
        .border_b(px(HAIRLINE))
        .border_color(color::LINE)
        .child(
            row_button(move || nav::push(Route::Account(detail.clone())))
                .px_0()
                .min_h(px(48.0))
                .gap_3()
                .min_w(px(0.0))
                .flex_1()
                .style_when(stack, |s| s.flex_grow(0.0).basis(auto()).w_full())
                .child(icon(glyph, 22.0, color::MUTED))
                .child(
                    text(name)
                        .flex_1()
                        .typo(Type::Body)
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(color::INK),
                ),
        )
        .child(
            row_button(move || nav::push(Route::AccountCheck(check.clone())))
                .accessibility_label(move || Some(spoken_action.clone().into()))
                .min_h(px(48.0))
                .px_0()
                .style_when(stack, |s| s.ml(px(34.0)))
                .child(
                    text(opening_action())
                        .typo(Type::Subhead)
                        .text_color(color::ACCENT_INK),
                ),
        )
        .into_element()
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
            .child(asset_group_title(if kind == AccountKind::Assets {
                s().cash_accounts
            } else {
                s().debt_accounts
            }))
            .children(own.into_iter().map(|a| {
                let balance = balances.get(a).copied();
                let checked = checks
                    .iter()
                    .filter(|c| c.account == *a)
                    .max_by_key(|c| c.checked_at);
                let glyph = if kind == AccountKind::Assets {
                    Icon::Wallet
                } else {
                    Icon::CreditCard
                };
                if balance.is_none() && checked.is_none() {
                    return new_account_row(a, glyph);
                }
                let detail = checked
                    .map(|c| {
                        format!(
                            "{} · {}",
                            s().account_checked,
                            s().short_date(Day(c.checked_at.date()))
                        )
                    })
                    .unwrap_or_else(|| s().account_unchecked.into());
                let name = crate::ui::currency::account_label(a);
                let route = a.to_string();
                let value = assets::displayed(a, balance.unwrap_or(0));
                asset_row(
                    name,
                    crate::ui::currency::format(value, a.currency()),
                    detail,
                    checked.is_none(),
                    glyph,
                    move || nav::push(Route::Account(route.clone())),
                )
                .into_element()
            }))
            .into_element(),
    )
}
