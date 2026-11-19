use super::*;

fn compact_holding_row() -> bool {
    font_scale() > 1.2 || window().width.0 < 350.0
}

pub fn section(closed: bool) -> impl IntoElement {
    dynamic(move || {
        let book = finance::holdings();
        let day = clock::today();
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
                            .map(|q| {
                                format!(
                                    "{} · {}",
                                    crate::i18n::statement_import::copy("Price date", "价格日期"),
                                    s().short_date(Day(q.day))
                                )
                            })
                            .unwrap_or_else(|| s().unpriced.into())
                    };
                    let value = p.value.unwrap_or(p.cost);
                    let label = format!(
                        "{}, {}, {}",
                        sec.name,
                        crate::ui::currency::format(value, sec.currency()),
                        status
                    );
                    view().child(
                        row_button(move || nav::push(Route::Holding(id.clone())))
                            .accessibility_label(move || Some(label.clone().into()))
                            .px_0()
                            .py_3()
                            .gap_3()
                            .min_h(px(56.0))
                            .child(crate::ui::icon(Icon::Chart, 22.0, color::MUTED))
                            .child(
                                view()
                                    .flex_1()
                                    .min_w(px(0.0))
                                    .flex_row()
                                    .items_center()
                                    .gap_3()
                                    .style_when(compact_holding_row, |s| {
                                        s.flex_col().items_start().gap_1()
                                    })
                                    .child(
                                        view()
                                            .flex_1()
                                            .min_w(px(0.0))
                                            .gap_1()
                                            .style_when(compact_holding_row, |s| s.w_full())
                                            .child(
                                                text(sec.name.clone())
                                                    .typo(Type::Headline)
                                                    .text_color(color::INK)
                                                    .number_of_lines(2),
                                            )
                                            .child(
                                                text(status)
                                                    .typo(Type::Caption)
                                                    .text_color(color::MUTED),
                                            ),
                                    )
                                    .child(amount(value, sec.currency(), Type::Headline)),
                            )
                            .child(crate::ui::icon(Icon::ChevronRight, 16.0, color::MUTED)),
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
