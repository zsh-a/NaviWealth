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

/// A management destination.
pub(super) fn nav_row(
    label: impl Fn() -> &'static str + Copy + 'static,
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
            text(label)
                .flex_1()
                .typo(Type::Headline)
                .text_color(color::INK),
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
            .child(asset_group_title(if kind == AccountKind::Assets {
                s().cash_accounts
            } else {
                s().debt_accounts
            }))
            .children(own.into_iter().map(|a| {
                let balance = balances.get(a).copied().unwrap_or(0);
                let checked = checks
                    .iter()
                    .filter(|c| c.account == *a)
                    .max_by_key(|c| c.checked_at);
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
