use super::*;

pub fn section(closed: bool) -> impl IntoElement {
    dynamic(move || {
        let book = finance::holdings_snapshot();
        let day = clock::today();
        let sources = crate::data::market::PriceSources::current();
        untracked(move || {
            let positions: Vec<_> = book
                .securities
                .iter()
                .filter_map(|sec| {
                    let p = book.position(sec, day.0).expect("validated holdings");
                    ((p.quantity == 0) == closed).then_some((sec, p))
                })
                .collect();
            if positions.is_empty() {
                return if closed {
                    text(|| s().no_closed_holdings)
                        .typo(Type::Body)
                        .text_color(color::MUTED)
                        .into_element()
                } else {
                    view().into_element()
                };
            }
            view()
                .gap_1()
                .child((!closed).then(|| {
                    text(|| s().holdings)
                        .typo(Type::Subhead)
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(color::MUTED)
                        .role(AccessibilityRole::Header)
                }))
                .children(positions.into_iter().map(|(sec, p)| {
                    let id = sec.id.clone();
                    let status = if closed {
                        s().holding_closed.into()
                    } else {
                        p.quote
                            .as_ref()
                            .map(|q| quote_caption(q, &sources, None))
                            .unwrap_or_else(|| s().unpriced.into())
                    };
                    let value = p.value.unwrap_or(p.cost);
                    super::super::assets::asset_row(
                        sec.name.clone(),
                        crate::ui::currency::format(value, sec.currency()),
                        status,
                        true,
                        Icon::Chart,
                        move || nav::push(Route::Holding(id.clone())),
                    )
                }))
                .into_element()
        })
    })
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
                            .child(section(true)),
                    ),
                ),
        )
}
