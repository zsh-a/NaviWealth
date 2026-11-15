//! Structured files never use recognition. Review is durable and explicit.
use super::parts::{bottom_bar, bottom_clearance, status_bar, top_bar};
use crate::{
    data::{finance, statement_import as data, tasks},
    i18n::{s, statement_import as tr},
    nav,
    ui::{
        Btn, Size, Type, Typo, color,
        field::{field, text_input},
        space,
        surface::{hairline, row_button},
    },
};
use finance_core::{
    account::{Account, AccountKind, defaults},
    currency::Currency,
    import::{Status, store::Correction},
    money,
    statement::{self, Kind},
};
use nsh_base::nav_page;
use nsh_core::{element::Screen, prelude::*};
use std::collections::BTreeSet;

#[derive(Clone, PartialEq)]
enum Panel {
    Method(String),
    Row(usize),
    Other(usize),
}
fn fail(error: Signal<Option<String>>, result: Result<(), String>) {
    if result.is_err() {
        error.set(Some(tr::failed().into()));
    }
}

pub fn statement_import_page() -> Screen {
    let panel = signal(None::<Panel>);
    let error = signal(None::<String>);
    let busy = signal(false);
    let shown = signal(50usize);
    let shown_issues = signal(50usize);
    let pick = move || {
        if busy.get_untracked() {
            return;
        }
        busy.set(true);
        error.set(None);
        tasks::spawn_app(async move {
            let request = nsh_core::picker::FilePickRequest::default().filter(
                nsh_core::file_dialog::FileFilter::new("Statement", ["csv", "xlsx", "txt"]),
            );
            let files = pick_files(request).await;
            if let Some(file) = files.first()
                && data::open_file(file.name.clone(), file.data.bytes().to_vec())
                    .await
                    .is_err()
            {
                error.try_set(Some(tr::unreadable().into()));
            }
            busy.try_set(false);
        });
    };
    nav_page().title(||SharedString::from(tr::title())).header_visible(false).status_bar(status_bar).child(
        view().flex_1().bg(color::CANVAS)
        .child(top_bar(||tr::title().into(),move||{if panel.get_untracked().is_some(){panel.set(None)}else{nav::pop()}},None))
        .child(scroll().flex_1().keyboard_dismiss_mode(KeyboardDismissMode::OnDrag).child(
            view().px(px(space::GUTTER)).pt_3().pb(move||px(bottom_clearance())).gap_4()
            .child(when(move||error.get().is_some(),move||text(move||error.get().unwrap_or_default()).typo(Type::Body).text_color(color::DANGER)))
            .child(dynamic(move||{
                if let Some(p)=panel.get(){return untracked(||edit_panel(p,panel,error).into_element())}
                let Some(draft)=data::current()else{return view().gap_4().child(text(tr::formats()).typo(Type::Body).text_color(color::MUTED)).child(Btn::primary().label(||tr::pick().into()).busy(move||busy.get()).on_press(pick)).into_element()};
                let report=data::report().unwrap();let rows=data::rows();
                let count=|status|rows.iter().filter(|r|r.status==status).count();
                let summary=format!("{} {} · {} {} · {} {} · {} {} · {} {}",count(Status::New),tr::ready(),count(Status::PossibleDuplicate),tr::copy("possible duplicates","疑似重复"),count(Status::Duplicate),tr::duplicate(),count(Status::NeedsAccount)+count(Status::NeedsAttention),tr::attention(),report.issues.len(),tr::copy("skipped","跳过"));
                let mut body=view().gap_3().child(text(draft.name.clone()).typo(Type::Title).text_color(color::INK)).child(text(summary).typo(Type::Subhead).text_color(color::MUTED));
                let methods:BTreeSet<_>=rows.iter().map(|c|c.method.clone()).collect();
                for method in methods{
                    let account=draft.rules.methods.get(report.provider.key()).and_then(|m|m.get(&method));
                    let label=format!("{} · {}",method,account.map(|a|a.name()).unwrap_or(tr::method()));
                    let m=method.clone();
                    body=body.child(row_button(move||panel.set(Some(Panel::Method(m.clone())))).child(text(label).typo(Type::Body).text_color(color::INK)));
                }
                body=body.child(text(tr::remember()).typo(Type::Caption).text_color(color::MUTED)).child(hairline(0.0));
                let row_count=rows.len();
                for (i,c) in rows.into_iter().enumerate().take(shown.get()){
                    let selected=draft.is_selected(i,&c);
                    let status=match c.status{Status::New=>tr::ready(),Status::Duplicate=>tr::duplicate(),Status::PossibleDuplicate=>tr::possible(),Status::NeedsAccount=>tr::method(),Status::NeedsAttention=>tr::attention()};
                    let title=format!("{} · {} {}",c.row.payee.clone().unwrap_or_else(||c.row.description.clone()),money::format(c.row.amount),c.row.currency);
                    let detail=format!("{} · {} · {}",c.row.at.date(),status,super::finance::category_label(&c.category));
                    let selectable=matches!(c.status,Status::New|Status::PossibleDuplicate)&&c.transaction.is_some();
                    let mut row=view().gap_1().py_2().child(text(title).typo(Type::Headline).text_color(color::INK)).child(text(detail).typo(Type::Subhead).text_color(color::MUTED));
                    let controls=view().flex_row().gap_2();
                    let controls=if selectable {controls.child(Btn::tonal().size(Size::Small).label(move||tr::copy(if selected{"Selected"}else{"Select"},if selected{"已选"}else{"选择"}).into()).on_press(move||fail(error,data::update(|d|{d.selected.insert(i,!selected);}))))}else{controls};
                    if c.status!=Status::Duplicate{
                        row=row.child(controls.child(Btn::ghost().size(Size::Small).label(||tr::copy("Correct","修改").into()).on_press(move||panel.set(Some(Panel::Row(i))))));
                    }
                    body=body.child(row).child(hairline(0.0));
                }
                if row_count>shown.get(){body=body.child(Btn::secondary().label(||tr::copy("Show 50 more rows","再显示 50 条").into()).on_press(move||shown.update(|n|*n+=50)));}
                if !report.issues.is_empty(){
                    body=body.child(text(tr::skip()).typo(Type::Headline).text_color(color::INK)).child(text(tr::issues()).typo(Type::Subhead).text_color(color::MUTED));
                    for issue in report.issues.into_iter().take(shown_issues.get()){
                        let reason=match issue.code{statement::IssueCode::InvalidDate=>tr::copy("Invalid date","日期无效"),statement::IssueCode::IgnoredStatus=>tr::copy("Not completed / refunded purchase","未完成或已退款的原购买记录"),statement::IssueCode::UnsupportedDirection=>tr::attention(),statement::IssueCode::InvalidAmount=>tr::copy("Invalid amount","金额无效"),statement::IssueCode::ZeroAmount=>tr::copy("Zero amount","零金额"),statement::IssueCode::MalformedRow=>tr::copy("Malformed row","行格式无效")};
                        body=body.child(text(format!("{} {} · {}",tr::copy("Line","第"),issue.line,reason)).typo(Type::Subhead).text_color(color::MUTED));
                    }
                }
                if report.candidates.saturating_sub(row_count)>shown_issues.get(){body=body.child(Btn::secondary().label(||tr::copy("Show 50 more skipped lines","再显示 50 条跳过行").into()).on_press(move||shown_issues.update(|n|*n+=50)));}
                body.child(Btn::ghost().label(||tr::copy("Discard this review","放弃本次核对").into()).on_press(move||{
                    // Visible second confirmation prevents losing a retained review.
                    let answer=nsh_base::alert_dialog().title(tr::copy("Discard import?","放弃导入？")).description(tr::copy("No transactions have been saved.","尚未保存任何交易。")).cancel("cancel",s().cancel).action("discard",tr::copy("Discard","放弃")).show();
                    tasks::spawn_app(async move { if matches!(answer.await,Ok(result) if result.action.as_deref()==Some("discard")) { fail(error,data::discard()); } });
                })).into_element()
            }))
        ))
        .child(when(move||data::has_draft()&&panel.get().is_none(),move||bottom_bar(
            Btn::primary().size(Size::Large).label(move||{
                let count=data::selected_count();
                format!("{} {count}",tr::copy("Import","导入")).into()
            }).disabled(move||data::selected_count()==0)
            .on_press(move||match data::confirm(){Ok(Some(count))=>{crate::ui::toast::show_toast(format!("{} {count}",tr::copy("Imported","已导入")),None);nav::pop();},Ok(None)=>error.set(Some(tr::stale().into())),Err(_)=>error.set(Some(tr::failed().into()))})
        )))
    )
}

fn edit_panel(
    p: Panel,
    panel: Signal<Option<Panel>>,
    error: Signal<Option<String>>,
) -> impl IntoElement {
    let Some(d) = data::current() else {
        return view();
    };
    let provider = statement::review(&d.text, "CNY").provider;
    let mut body = view().gap_3();
    match p {
        Panel::Method(method) => {
            let currencies: BTreeSet<_> = data::rows()
                .iter()
                .filter(|c| c.method == method)
                .filter_map(|c| Currency::parse(&c.row.currency))
                .collect();
            let source_currency = currencies.iter().next().copied().unwrap_or_default();
            body = body.child(
                text(method.clone())
                    .typo(Type::Title)
                    .text_color(color::INK),
            );
            for account in finance::accounts()
                .into_iter()
                .filter(|a| a.is_cash() && currencies.contains(&a.currency()))
            {
                let label = format!(
                    "{} · {}",
                    account.name(),
                    if account.kind() == AccountKind::Assets {
                        s().asset_account
                    } else {
                        s().liability_account
                    }
                );
                let method = method.clone();
                body = body.child(
                    row_button(move || {
                        fail(
                            error,
                            data::update(|d| {
                                d.rules.remember_method(provider, &method, account.clone())
                            }),
                        );
                        panel.set(None)
                    })
                    .child(text(label).typo(Type::Body).text_color(color::INK)),
                );
            }
            body = body.child(new_account(source_currency, move |account| {
                let m = method.clone();
                fail(
                    error,
                    data::update(|d| d.rules.remember_method(provider, &m, account)),
                );
                panel.set(None)
            }));
        }
        Panel::Other(i) => {
            let Some(row) = data::rows().get(i).cloned() else {
                return body;
            };
            let source_currency = Currency::parse(&row.row.currency).unwrap_or_default();
            let own = d
                .rules
                .methods
                .get(provider.key())
                .and_then(|m| m.get(&row.method))
                .cloned();
            body = body.child(text(tr::other()).typo(Type::Title).text_color(color::INK));
            for account in finance::accounts().into_iter().filter(|a| {
                a.is_cash() && a.currency() == source_currency && Some(a) != own.as_ref()
            }) {
                let label = account.to_string();
                body = body.child(
                    row_button(move || {
                        fail(
                            error,
                            data::update(|d| {
                                if let Some(c) = d.corrections.get_mut(&i) {
                                    c.other = Some(account.clone())
                                }
                            }),
                        );
                        panel.set(Some(Panel::Row(i)))
                    })
                    .child(text(label).typo(Type::Body).text_color(color::INK)),
                );
            }
            body = body.child(new_account(source_currency, move |account| {
                fail(
                    error,
                    data::update(|d| {
                        if let Some(c) = d.corrections.get_mut(&i) {
                            c.other = Some(account)
                        }
                    }),
                );
                panel.set(Some(Panel::Row(i)))
            }));
        }
        Panel::Row(i) => {
            let Some(c) = data::rows().get(i).cloned() else {
                return body;
            };
            body = body.child(
                text(c.row.description.clone())
                    .typo(Type::Title)
                    .text_color(color::INK),
            );
            let source_currency = Currency::parse(&c.row.currency).unwrap_or_default();
            for (kind, label) in [
                (Kind::Expense, s().spending),
                (Kind::Income, s().income),
                (Kind::Refund, tr::refund()),
                (Kind::TransferIn, tr::incoming()),
                (Kind::TransferOut, tr::outgoing()),
            ] {
                body = body.child(
                    row_button(move || {
                        fail(
                            error,
                            data::update(|d| {
                                let category = if kind == Kind::Income {
                                    defaults::other_income()
                                } else {
                                    defaults::other_expense()
                                }
                                .in_currency(source_currency);
                                d.corrections.insert(
                                    i,
                                    Correction {
                                        kind,
                                        category,
                                        other: None,
                                    },
                                );
                                d.selected.remove(&i);
                            }),
                        );
                        panel.set(None)
                    })
                    .child(text(label).typo(Type::Body).text_color(color::INK)),
                );
            }
            if matches!(c.row.kind, Kind::TransferIn | Kind::TransferOut) {
                body = body.child(Btn::tonal().label(|| tr::other().into()).on_press(move || {
                    let _ = data::update(|d| {
                        d.corrections.entry(i).or_insert(Correction {
                            kind: c.row.kind,
                            category: c.category.clone(),
                            other: None,
                        });
                    });
                    panel.set(Some(Panel::Other(i)))
                }));
            } else {
                if let Some(payee) = c.row.payee.clone() {
                    let category = c.category.clone();
                    body = body.child(
                        Btn::tonal()
                            .label(|| {
                                tr::copy(
                                    "Remember this category for this payee",
                                    "记住此交易对方的分类",
                                )
                                .into()
                            })
                            .on_press(move || {
                                fail(
                                    error,
                                    data::update(|d| {
                                        d.rules.remember_payee(&payee, category.clone())
                                    }),
                                );
                                panel.set(None)
                            }),
                    );
                }
                for category in defaults::all()
                    .into_iter()
                    .map(|a| a.in_currency(source_currency))
                    .filter(|a| {
                        a.kind()
                            == if c.row.kind == Kind::Income {
                                AccountKind::Income
                            } else {
                                AccountKind::Expenses
                            }
                    })
                {
                    let label = super::finance::category_label(&category);
                    let kind = c.row.kind;
                    body = body.child(
                        row_button(move || {
                            fail(
                                error,
                                data::update(|d| {
                                    d.corrections.insert(
                                        i,
                                        Correction {
                                            kind,
                                            category: category.clone(),
                                            other: None,
                                        },
                                    );
                                }),
                            );
                            panel.set(None)
                        })
                        .child(text(label).typo(Type::Body).text_color(color::INK)),
                    );
                }
            }
        }
    }
    body
}
fn new_account(source_currency: Currency, save: impl Fn(Account) + 'static) -> impl IntoElement {
    let name = signal(String::new());
    let kind = signal(AccountKind::Assets);
    let currency = signal(source_currency);
    view()
        .gap_3()
        .pt_4()
        .child(
            text(tr::copy("New account", "新建账户"))
                .typo(Type::Headline)
                .text_color(color::INK),
        )
        .child(
            view()
                .flex_row()
                .gap_2()
                .child(
                    Btn::tonal()
                        .label(|| s().asset_account.into())
                        .on_press(move || kind.set(AccountKind::Assets)),
                )
                .child(
                    Btn::tonal()
                        .label(|| s().liability_account.into())
                        .on_press(move || kind.set(AccountKind::Liabilities)),
                ),
        )
        .child(
            text(move || {
                if kind.get() == AccountKind::Assets {
                    s().asset_account
                } else {
                    s().liability_account
                }
            })
            .typo(Type::Caption)
            .text_color(color::MUTED),
        )
        .child(
            view()
                .flex_row()
                .gap_2()
                .children(Currency::ALL.into_iter().map(move |c| {
                    Btn::tonal()
                        .label(move || {
                            if currency.get() == c {
                                format!("✓ {c}").into()
                            } else {
                                c.code().into()
                            }
                        })
                        .on_press(move || currency.set(c))
                })),
        )
        .child(field(
            || tr::copy("Account name", "账户名称"),
            text_input(name).label(|| tr::copy("Account name", "账户名称")),
        ))
        .child(
            Btn::secondary()
                .label(|| tr::copy("Use account", "使用此账户").into())
                .disabled(move || Account::new_in(kind.get(), &name.get(), currency.get()).is_err())
                .on_press(move || {
                    if let Ok(a) = Account::new_in(
                        kind.get_untracked(),
                        &name.get_untracked(),
                        currency.get_untracked(),
                    ) {
                        save(a)
                    }
                }),
        )
}
