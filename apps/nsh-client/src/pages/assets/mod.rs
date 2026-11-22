//! Assets answers what the recorded ledger says the owner owns. Account
//! details and balance observations use the same journal as Today/Records.
pub(crate) mod current;
mod editor;
mod mini;
mod overview;
mod overview_parts;
mod summary;
mod trend;
pub use overview::assets_tab;
pub use trend::history_page;

use crate::{
    data::{clock, finance},
    domain::meal::Day,
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Type, Typo, Variant, color, icon, radius, space,
        surface::{HAIRLINE, group_label, hairline, row_button},
        toast::toast_view,
    },
};
use navi_finance::{
    account::{Account, AccountKind, defaults},
    assets,
    journal::{self, Transaction},
};
use nsh_base::nav_page;
use nsh_core::{element::Screen, prelude::*};

/// Group display digits without changing exact minor units or editable input.
fn display_money(value: i64) -> String {
    crate::ui::currency::grouped(value)
}

pub(super) fn amount(value: i64, style: Type) -> impl IntoElement {
    amount_in(value, style, navi_finance::currency::Currency::CNY)
}

pub(super) fn amount_in(
    value: i64,
    style: Type,
    currency: navi_finance::currency::Currency,
) -> impl IntoElement {
    text(crate::ui::currency::format(value, currency))
        .typo(style)
        .number_of_lines(1)
        .shrink_to_fit(0.65)
        .min_w(px(0.0))
        .flex_shrink(1.0_f32)
        .tabular_nums()
        .text_color(color::INK)
}

pub(super) fn asset_group_title(label: impl IntoReactive<SharedString>) -> impl IntoElement {
    text(label)
        .typo(Type::Body)
        .font_weight(FontWeight::SEMIBOLD)
        .text_color(color::INK)
        .role(AccessibilityRole::Header)
        .pb_1()
}

/// One alignment grid for the account and holding sections, including their spoken status.
/// Each row runs from gutter to gutter on the page canvas.
pub(super) fn asset_row(
    name: String,
    amount: String,
    status: String,
    show_status: bool,
    glyph: Icon,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    let label = format!("{name}, {amount}, {status}");
    let long_amount = amount.chars().count() >= 16;
    let stacked = move || font_scale() > 1.2 || window().width.0 < 350.0 || long_amount;
    row_button(press)
        .accessibility_label(move || Some(label.clone().into()))
        .px_0()
        .py_2()
        .min_h(px(64.0))
        .border_b(px(HAIRLINE))
        .border_color(color::LINE)
        .gap_3()
        .child(icon(glyph, 22.0, color::MUTED))
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .flex_row()
                .items_center()
                .gap_3()
                .style_when(stacked, |s| s.flex_col().items_start().gap_1())
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .gap_1()
                        .style_when(stacked, |s| s.w_full().flex_grow(0.0).basis(auto()))
                        .child(
                            text(name)
                                .typo(Type::Body)
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(color::INK),
                        )
                        .child(
                            show_status
                                .then(|| text(status).typo(Type::Caption).text_color(color::MUTED)),
                        ),
                )
                .child(
                    text(amount)
                        .test_id("asset-row-value")
                        .style_when(stacked, |s| s.w_full())
                        .typo(Type::Body)
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(color::INK)
                        .tabular_nums()
                        .number_of_lines(1)
                        .shrink_to_fit(0.65)
                        .min_w(px(0.0)),
                ),
        )
        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
}

pub fn account_page(name: &str) -> Screen {
    let own = signal(Account::parse(name).expect("account route created from a valid account"));
    let balance = signal(editor::take_created_check(name));
    let rename = signal(false);
    let transaction = signal(None::<String>);
    let shown = signal(50usize);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::preview::balance_opened(balance);
    nav_page()
        .title(move || own.with(|a| a.name().to_owned()))
        .header_visible(false)
        .status_bar(super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::parts::top_bar(
                    move || own.with(|a| a.name().to_owned().into()),
                    nav::pop,
                    Some(
                        IconBtn::new(Icon::Pencil, || s().rename_account.into())
                            .variant(Variant::Ghost)
                            .on_press(move || rename.set(true))
                            .into_element(),
                    ),
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .pb_safe_area_plus(px(90.0))
                            .gap_5()
                            .child(
                                view()
                                    .gap_3()
                                    .pt_4()
                                    .child(dynamic(move || {
                                        let a = own.get();
                                        let book = journal::balance_on(
                                            finance::transactions_snapshot().iter(),
                                            &a,
                                            clock::today().0,
                                        );
                                        view()
                                            .gap_3()
                                            .child(
                                                text(if a.kind() == AccountKind::Liabilities {
                                                    s().account_debt
                                                } else {
                                                    s().account_balance
                                                })
                                                .typo(Type::Headline)
                                                .text_color(color::BODY),
                                            )
                                            .child(amount_in(
                                                assets::displayed(&a, book),
                                                Type::Display,
                                                a.currency(),
                                            ))
                                    }))
                                    .child(check_history(own, transaction))
                                    .child(
                                        Btn::tonal()
                                            .label(|| s().check_balance.into())
                                            .on_press(move || balance.set(true)),
                                    ),
                            )
                            .child(
                                text(|| s().account_activity)
                                    .typo(Type::Title)
                                    .text_color(color::INK),
                            )
                            .child(dynamic(move || {
                                let a = own.get();
                                let mut entries: Vec<_> = finance::transactions()
                                    .into_iter()
                                    .filter(|t| t.postings.iter().any(|p| p.account == a))
                                    .collect();
                                entries.reverse();
                                let more = entries.len() > shown.get();
                                entries.truncate(shown.get());
                                untracked(move || {
                                    if entries.is_empty() {
                                        return text(|| s().account_activity_empty)
                                            .typo(Type::Body)
                                            .text_color(color::MUTED)
                                            .into_element();
                                    }
                                    view()
                                        .children(entries.into_iter().map(|t| {
                                            let id = t.id.clone();
                                            let value = assets::displayed(&a, t.amount_in(&a));
                                            let caption = format!(
                                                "{} · {}",
                                                s().long_date(Day(t.at.date())),
                                                t.note
                                            );
                                            let title = super::finance::transaction_title(&t);
                                            let label = format!(
                                                "{title}, {}",
                                                crate::ui::currency::format(value, a.currency())
                                            );
                                            view()
                                                .child(
                                                    row_button(move || {
                                                        transaction.set(Some(id.clone()))
                                                    })
                                                    .accessibility_label(move || {
                                                        Some(label.clone().into())
                                                    })
                                                    .px_0()
                                                    .py_3()
                                                    .gap_3()
                                                    .child(
                                                        view()
                                                            .flex_1()
                                                            .min_w(px(0.0))
                                                            .gap_1()
                                                            .child(
                                                                text(title)
                                                                    .typo(Type::Headline)
                                                                    .text_color(color::INK)
                                                                    .number_of_lines(1),
                                                            )
                                                            .child(
                                                                text(
                                                                    caption
                                                                        .trim_end_matches(" · ")
                                                                        .to_owned(),
                                                                )
                                                                .typo(Type::Subhead)
                                                                .text_color(color::MUTED)
                                                                .number_of_lines(1),
                                                            ),
                                                    )
                                                    .child(amount_in(
                                                        value,
                                                        Type::Figure,
                                                        a.currency(),
                                                    )),
                                                )
                                                .child(hairline(0.0))
                                        }))
                                        .child(more.then(|| {
                                            Btn::secondary()
                                                .label(|| s().show_earlier.into())
                                                .on_press(move || shown.update(|n| *n += 50))
                                        }))
                                        .into_element()
                                })
                            })),
                    ),
                )
                .child(
                    view()
                        .absolute()
                        .inset_0()
                        .pointer_events(PointerEvents::BoxNone)
                        .style_when(
                            move || balance.get() || rename.get() || transaction.get().is_some(),
                            |s| s.hidden(),
                        )
                        .child(toast_view(|| 24.0)),
                )
                .child(editor::account_editor(rename, Some(own)))
                .child(editor::balance_editor(balance, own))
                .child(super::finance::finance_editor(transaction)),
        )
}

/// Each saved check has an observation, including matches that did not post
/// anything. Its original difference lives in the linked posting; recomputing
/// today's journal at the historical date would include subsequent backfills.
fn check_history(own: Signal<Account>, entry: Signal<Option<String>>) -> AnyElement {
    let open = signal(false);
    let shown = signal(20usize);
    dynamic(move || {
        let account = own.get();
        let checks = finance::checks_snapshot();
        let Some(latest) = checks.iter().rev().find(|c| c.account == account) else {
            return text(s().account_unchecked)
                .typo(Type::Subhead)
                .text_color(color::MUTED)
                .into_element();
        };
        let latest = Day(latest.checked_at.date());
        view()
            .gap_2()
            .child(
                crate::ui::surface::disclosure(open, move || {
                    format!("{} · {}", s().account_checked, s().short_date(latest)).into()
                })
                .accessibility_label(move || {
                    let title = crate::i18n::catalog::copy("Balance check history", "余额核对历史");
                    Some(
                        format!(
                            "{title}, {} · {}",
                            s().account_checked,
                            s().short_date(latest)
                        )
                        .into(),
                    )
                }),
            )
            .child(when(
                move || open.get(),
                move || {
                    let account = account.clone();
                    let checks = checks.clone();
                    dynamic(move || {
                        let txs = finance::transactions_snapshot();
                        let linked = txs
                            .iter()
                            .map(|t| (t.id.as_str(), t))
                            .collect::<std::collections::HashMap<_, _>>();
                        let limit = shown.get();
                        let mut rows = checks
                            .iter()
                            .rev()
                            .filter(|c| c.account == account)
                            .take(limit + 1)
                            .collect::<Vec<_>>();
                        let more = rows.len() > limit;
                        rows.truncate(limit);
                        view()
                            .children(
                                rows.into_iter().map(|c| {
                                    check_row(c, linked.get(c.id.as_str()).copied(), entry)
                                }),
                            )
                            .child(more.then(|| {
                                Btn::secondary()
                                    .label(|| s().show_earlier.into())
                                    .on_press(move || shown.update(|n| *n += 20))
                            }))
                    })
                },
            ))
            .into_element()
    })
    .into_element()
}

fn check_row(
    check: &navi_finance::repository::BalanceCheck,
    transaction: Option<&Transaction>,
    entry: Signal<Option<String>>,
) -> AnyElement {
    use crate::i18n::catalog::copy;
    let account = &check.account;
    let observation =
        crate::ui::currency::format(assets::displayed(account, check.actual), account.currency());
    let effective = s().long_date(Day(check.day));
    let time = clock::clock_time(
        check.checked_at.hour() as u8,
        check.checked_at.minute() as u8,
    );
    let stamp = if check.checked_at.date() == check.day {
        format!("{effective} · {time}")
    } else {
        format!(
            "{effective} · {} {} {time}",
            copy("Checked", "核对于"),
            s().axis_date(Day(check.checked_at.date()), true)
        )
    };
    let linked = transaction.filter(|t| {
        matches!(t.source, journal::Source::BalanceCheck)
            && t.postings.iter().any(|p| &p.account == account)
    });
    let outcome = if let Some(t) = linked {
        let delta = assets::displayed(account, t.amount_in(account));
        format!(
            "{} {}",
            balance_title(t).unwrap_or(s().balance_adjustment),
            crate::ui::currency::signed(delta, account.currency())
        )
    } else if transaction.is_some() {
        copy("Original correction unavailable", "原核对凭证不可用").to_owned()
    } else {
        copy("Matched at the time", "核对时相符").to_owned()
    };
    let label = format!("{stamp}, {observation}, {outcome}");
    let scaled = || font_scale() > 1.2 || window().width.0 < 350.0;
    let summary = view()
        .flex_1()
        .min_w(px(0.0))
        .gap_1()
        .child(
            text(stamp)
                .typo(Type::Caption)
                .text_color(color::MUTED)
                .tabular_nums(),
        )
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .style_when(scaled, |s| s.flex_col().items_start())
                .child(
                    text(observation)
                        .typo(Type::Figure)
                        .text_color(color::INK)
                        .tabular_nums(),
                )
                .child(
                    text(outcome)
                        .typo(Type::Subhead)
                        .text_color(color::BODY)
                        .tabular_nums(),
                ),
        );
    let row = if let Some(t) = linked {
        let id = t.id.clone();
        row_button(move || entry.set(Some(id.clone())))
            .accessibility_label(Some(label.into()))
            .min_h(px(48.0))
            .px_0()
            .py_2()
            .gap_2()
            .child(summary)
            .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
            .into_element()
    } else {
        view().py_2().child(summary).into_element()
    };
    view().child(row).child(hairline(0.0)).into_element()
}

pub(super) fn balance_title(t: &Transaction) -> Option<&'static str> {
    if t.postings
        .iter()
        .any(|p| p.account == defaults::opening().in_currency(p.account.currency()))
    {
        Some(s().opening_balance)
    } else if t
        .postings
        .iter()
        .any(|p| p.account == defaults::adjustment().in_currency(p.account.currency()))
    {
        Some(s().balance_adjustment)
    } else {
        None
    }
}

/// Balance entries remain readable from Today/Records as well as an account.
pub(super) fn balance_entry(t: Transaction, open: Signal<Option<String>>) -> AnyElement {
    let error = signal(None::<String>);
    let asking = signal(false);
    let removed = t.clone();
    let own = t.own_postings().next().map(|p| p.account.clone());
    let header = view()
        .flex_row()
        .items_center()
        .child(
            text(balance_title(&t).unwrap_or(s().transactions))
                .typo(Type::Title)
                .text_color(color::INK)
                .flex_1()
                .min_w(px(0.0)),
        )
        .child(
            Btn::ghost()
                .label(|| s().undo.into())
                .disabled(move || asking.get())
                .on_press(move || {
                    super::finance::confirm_delete(removed.clone(), open, error, asking)
                })
                .accessibility_label(|| Some(s().revoke_balance.into())),
        )
        .child(
            Btn::ghost()
                .label(|| s().close.into())
                .disabled(move || asking.get())
                .on_press(move || open.set(None)),
        );
    let body = view()
        .gap_4()
        .child(
            text(s().long_date(Day(t.at.date())))
                .typo(Type::Body)
                .text_color(color::MUTED),
        )
        .children(t.own_postings().map(|p| {
            view()
                .gap_2()
                .child(
                    text(p.account.name().to_owned())
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child(amount_in(
                    assets::displayed(&p.account, p.amount),
                    Type::Lead,
                    p.account.currency(),
                ))
        }))
        .child(
            text(|| s().balance_readonly)
                .typo(Type::Body)
                .text_color(color::MUTED),
        );
    let action = view()
        .gap_2()
        .child(crate::ui::field::note(
            move || error.get().map(Into::into),
            || true,
        ))
        .child(
            Btn::primary()
                .label(|| s().view_account.into())
                .disabled(move || asking.get())
                .on_press(move || {
                    open.set(None);
                    if let Some(a) = &own {
                        nav::push(Route::Account(a.to_string()));
                    }
                }),
        );
    crate::ui::sheet::task_sheet(
        move || open.get().is_some(),
        move || {
            if !asking.get_untracked() {
                open.set(None);
            }
        },
        header,
        body,
        action,
    )
    .into_element()
}
