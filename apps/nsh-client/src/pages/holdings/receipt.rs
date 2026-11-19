use super::*;

pub(in crate::pages) fn trade_receipt(id: &str, close: impl Fn() + Copy + 'static) -> AnyElement {
    let book = finance::holdings();
    let Some(t) = book.trades.iter().find(|t| t.id == id).cloned() else {
        return view().into_element();
    };
    let sec = book.securities.iter().find(|s| s.id == t.security).unwrap();
    let error = signal(None::<String>);
    let open = signal(true);
    let close = move || {
        open.set(false);
        close();
    };
    let header = view()
        .flex_row()
        .items_center()
        .child(
            text(format!("{} · {}", kind_label(t.kind), sec.name))
                .typo(Type::Title)
                .text_color(color::INK)
                .flex_1(),
        )
        .child(Btn::ghost().label(|| s().close.into()).on_press(close));
    let body = view()
        .gap_3()
        .child(
            text(s().long_date(Day(t.at.date())))
                .typo(Type::Body)
                .text_color(color::MUTED),
        )
        .child(if t.kind == Kind::Dividend {
            pair(
                s().dividend_amount,
                crate::ui::currency::format(t.amount, sec.currency()),
            )
            .into_element()
        } else {
            view()
                .gap_3()
                .child(pair(s().quantity, holdings::format_units(t.quantity)))
                .child(pair(
                    s().trade_price,
                    crate::ui::currency::unit_price(t.price, sec.currency()),
                ))
                .into_element()
        })
        .child(pair(
            s().fee,
            crate::ui::currency::format(t.fee, sec.currency()),
        ))
        .child(
            t.cash
                .as_ref()
                .map(|a| pair(s().cash_account, a.name().to_owned())),
        );
    let action = view()
        .gap_2()
        .child(note(move || error.get().map(Into::into), || true))
        .child(
            Btn::new(Variant::Danger)
                .label(|| s().remove_trade.into())
                .on_press(move || {
                    let id = t.id.clone();
                    let answer = alert_dialog()
                        .title(s().holding_delete_title)
                        .description(s().holding_delete_body)
                        .cancel("keep", s().cancel)
                        .destructive("delete", s().remove_trade)
                        .show();
                    spawn(async move {
                        if answer
                            .await
                            .is_ok_and(|r| r.action.as_deref() == Some("delete"))
                        {
                            match finance::remove_trade(&id) {
                                Ok(()) => {
                                    close();
                                    show_toast(s().trade_deleted, None);
                                }
                                Err(e) => {
                                    log::error!("holdings: delete failed: {e}");
                                    error.set(Some(failure(&e).into()));
                                }
                            }
                        }
                    });
                }),
        );
    crate::ui::sheet::task_sheet(move || open.get(), close, header, body, action).into_element()
}
