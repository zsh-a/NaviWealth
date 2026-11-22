use super::*;

pub fn section() -> impl IntoElement {
    dynamic(move || {
        let book = finance::holdings_snapshot();
        let day = clock::today();
        let sources = crate::data::market::PriceSources::current();
        untracked(move || {
            view()
                .child(super::super::assets::asset_group_title(|| s().holdings))
                .children(book.securities.iter().filter_map(|sec| {
                    let p = book.position(sec, day.0).expect("validated holdings");
                    if p.quantity == 0 {
                        return None;
                    }
                    let id = sec.id.clone();
                    let status = p
                        .quote
                        .as_ref()
                        .map(|q| quote_caption(q, &sources, false))
                        .unwrap_or_else(|| s().unpriced.into());
                    Some(super::super::assets::asset_row(
                        sec.name.clone(),
                        crate::ui::currency::format(p.value.unwrap_or(p.cost), sec.currency()),
                        status,
                        true,
                        Icon::Chart,
                        move || nav::push(Route::Holding(id.clone())),
                    ))
                }))
                .into_element()
        })
    })
}

pub(crate) fn closed_holdings() -> Vec<(jiff::civil::DateTime, Security)> {
    let book = finance::holdings_snapshot();
    let day = clock::today();
    let mut closed: Vec<_> = book
        .securities
        .iter()
        .filter_map(|security| {
            let (position, _) =
                holdings::replay(security, &book.trades, day.0).expect("validated holdings");
            Some((position.closed_at?, security.clone()))
        })
        .collect();
    closed.sort_by_key(|(at, _)| std::cmp::Reverse(*at));
    closed
}

fn closed_list() -> AnyElement {
    let closed = closed_holdings();
    if closed.is_empty() {
        return text(|| s().no_closed_holdings)
            .typo(Type::Body)
            .text_color(color::MUTED)
            .into_element();
    }
    view()
        .children(closed.into_iter().map(|(at, security)| {
            super::super::assets::asset_row(
                security.name,
                s().axis_date(Day(at.date()), true),
                s().holding_closed.into(),
                false,
                Icon::Chart,
                move || nav::push(Route::Holding(security.id.clone())),
            )
        }))
        .into_element()
}

pub fn closed_page() -> Screen {
    nav_page()
        .title(|| s().closed_holdings)
        .header_visible(false)
        .status_bar(crate::pages::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(crate::pages::parts::top_bar(
                    || s().closed_holdings.into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(crate::ui::space::GUTTER))
                            .pt_4()
                            .pb_safe_area_plus(px(24.0))
                            .child(dynamic(closed_list)),
                    ),
                ),
        )
}
