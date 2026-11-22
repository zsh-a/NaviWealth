use super::*;
use crate::i18n::catalog::copy;
use crate::ui::{field::note, toast::show_toast};

pub(super) fn archived_title() -> &'static str {
    copy("Inactive accounts", "已停用账户")
}

pub(super) fn archived_status() -> &'static str {
    copy("Inactive", "已停用")
}

pub(super) fn account_action(own: Signal<Account>, close: impl Fn() + 'static) -> impl IntoElement {
    let archived = computed(move || finance::archived_accounts().contains(&own.get()));
    let failed = signal(false);
    view()
        .gap_1()
        .child(
            Btn::ghost()
                .label(move || {
                    if archived.get() {
                        copy("Reactivate account", "恢复使用").into()
                    } else {
                        copy("Deactivate account", "停用账户").into()
                    }
                })
                .on_press(move || {
                    let deactivate = !archived.get_untracked();
                    if let Err(error) =
                        finance::set_account_archived(&own.get_untracked(), deactivate)
                    {
                        log::error!("assets: could not change account status: {error}");
                        failed.set(true);
                        return;
                    }
                    failed.set(false);
                    close();
                    show_toast(
                        if deactivate {
                            copy("Account deactivated", "账户已停用")
                        } else {
                            copy("Account reactivated", "账户已恢复")
                        },
                        None,
                    );
                }),
        )
        .child(note(
            move || failed.get().then(|| s().error_transaction_storage.into()),
            || true,
        ))
}

pub fn archived_accounts_page() -> Screen {
    nav_page()
        .title(archived_title)
        .header_visible(false)
        .status_bar(crate::pages::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(crate::pages::parts::top_bar(
                    || archived_title().into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .pt_4()
                            .pb_safe_area_plus(px(24.0))
                            .child(dynamic(archived_list)),
                    ),
                ),
        )
}

fn archived_list() -> AnyElement {
    let accounts = finance::archived_accounts();
    if accounts.is_empty() {
        return text(copy("No inactive accounts", "暂无已停用账户"))
            .typo(Type::Body)
            .text_color(color::MUTED)
            .into_element();
    }
    let entries = finance::transactions_snapshot();
    let today = clock::today().0;
    let balances = journal::balances(entries.iter().filter(|t| t.at.date() <= today));
    let checks = finance::checks_snapshot();
    view()
        .children(accounts.iter().map(|a| {
            let balance = balances
                .get(a)
                .copied()
                .or_else(|| latest_checked_day(&checks, a).map(|_| 0));
            let value = balance
                .map(|v| crate::ui::currency::format(assets::displayed(a, v), a.currency()))
                .unwrap_or_else(|| "—".into());
            let purpose = crate::ui::account_purpose::description(a, finance::account_purpose(a));
            let glyph = if a.kind() == AccountKind::Liabilities {
                Icon::CreditCard
            } else {
                Icon::Wallet
            };
            let route = a.to_string();
            asset_row(
                a.name().to_owned(),
                value,
                format!("{purpose} · {}", a.currency()),
                true,
                glyph,
                move || nav::push(Route::Account(route.clone())),
            )
        }))
        .into_element()
}
