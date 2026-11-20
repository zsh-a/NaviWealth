use super::*;
use crate::ui::surface::card;

pub(super) fn net_summary(
    valued: navi_finance::holdings::ValuedOverview,
    includes_holdings: bool,
    at_cost: Vec<(String, String)>,
    history: super::trend::NetWorthHistory,
) -> impl IntoElement {
    let net = valued.snapshot;
    let partial = !valued.missing.is_empty();
    let basis = if includes_holdings {
        s().valuation_recorded
    } else {
        s().valuation_book
    };
    let footer = history.change().map(|delta| {
        format!(
            "{} {}",
            s().net_change_30d,
            crate::ui::currency::signed(delta, navi_finance::currency::Currency::CNY)
        )
    });
    let history_label = footer
        .as_ref()
        .map(|change| format!("{}, {change}", s().asset_history))
        .unwrap_or_else(|| s().asset_history.to_owned());
    let expanded = signal(false);
    let count = at_cost.len();
    card()
        .p_5()
        .gap_3()
        .child(
            view()
                .gap_1()
                .child(
                    view()
                        .flex_row()
                        .items_center()
                        .gap_2()
                        .style_when(|| font_scale() > 1.2, |s| s.flex_col().items_start())
                        .child(
                            text(if partial {
                                crate::i18n::statement_import::copy(
                                    "Known value · CNY",
                                    "已折算净资产 · CNY",
                                )
                            } else {
                                s().portfolio_net
                            })
                            .typo(Type::Subhead)
                            .text_color(color::MUTED)
                            .flex_1(),
                        )
                        .child((count > 0).then(|| {
                            row_button(move || expanded.update(|v| *v = !*v))
                                .min_h(px(48.0))
                                .py_1()
                                .px_0()
                                .gap_1()
                                .accessibility_label(move || Some(s().cost_holdings(count).into()))
                                .child(
                                    text(s().cost_count(count))
                                        .typo(Type::Caption)
                                        .text_color(color::BODY),
                                )
                                .child(dynamic(move || {
                                    icon(
                                        if expanded.get() {
                                            Icon::ChevronDown
                                        } else {
                                            Icon::ChevronRight
                                        },
                                        14.0,
                                        color::MUTED,
                                    )
                                    .into_element()
                                }))
                        })),
                )
                .child(net_figure(net.net))
                .child(partial.then(|| {
                    let codes = valued
                        .missing
                        .iter()
                        .map(|c| c.code())
                        .collect::<Vec<_>>()
                        .join(" / ");
                    row_button(|| nav::push(Route::ExchangeRates))
                        .px_0()
                        .py_1()
                        .min_h(px(48.0))
                        .child(
                            text(s().excluded_currencies(&codes))
                                .typo(Type::Subhead)
                                .text_color(color::CAUTION)
                                .flex_1(),
                        )
                        .child(icon(Icon::ChevronRight, 16.0, color::CAUTION))
                })),
        )
        .child(
            view()
                .flex_row()
                .gap_4()
                .py_1()
                .style_when(
                    || font_scale() > 1.2 || window().width.0 < 350.0,
                    |s| s.flex_col(),
                )
                .child(total(s().total_assets, net.assets))
                .child(total(s().total_debt, net.debt)),
        )
        .child(when(
            move || expanded.get(),
            move || {
                view()
                    .test_id("cost-holdings")
                    .children(at_cost.iter().cloned().map(|(id, name)| {
                        row_button(move || nav::push(Route::Holding(id.clone())))
                            .min_h(px(48.0))
                            .child(text(name).typo(Type::Body).text_color(color::INK))
                    }))
            },
        ))
        .child(hairline(0.0))
        .child(
            row_button(|| nav::push(Route::AssetHistory))
                .accessibility_label(move || Some(history_label.clone().into()))
                .px_0()
                .py_1()
                .min_h(px(48.0))
                .flex_col()
                .items_stretch()
                .gap_1()
                .child(super::mini::sparkline(&history))
                .child(
                    view()
                        .flex_row()
                        .items_center()
                        .gap_2()
                        .child(
                            text(footer.unwrap_or_else(|| basis.into()))
                                .typo(Type::Caption)
                                .tabular_nums()
                                .text_color(color::MUTED)
                                .flex_1(),
                        )
                        .child(
                            text(|| s().asset_history)
                                .typo(Type::Subhead)
                                .text_color(color::INK),
                        )
                        .child(icon(Icon::ChevronRight, 16.0, color::MUTED)),
                ),
        )
}

fn total(label: &'static str, value: i64) -> impl IntoElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap_1()
        .child(text(label).typo(Type::Caption).text_color(color::MUTED))
        .child(amount(value, Type::Body))
}

fn net_figure(value: i64) -> impl IntoElement {
    let written = display_money(value);
    let (whole, fraction) = written.split_once('.').expect("money decimals");
    view()
        .flex_row()
        .items_baseline()
        .flex_wrap()
        .min_w(px(0.0))
        .accessible(true)
        .label(move || crate::ui::currency::format(value, navi_finance::currency::Currency::CNY))
        .child(
            text(if value < 0 { "−¥" } else { "¥" })
                .typo(Type::Figure)
                .text_color(color::MUTED)
                .mr_1(),
        )
        .child(
            text(whole.trim_start_matches('-').to_owned())
                .typo(Type::Display)
                .min_w(px(0.0))
                .flex_shrink(1.0_f32)
                .number_of_lines(1)
                .shrink_to_fit(0.35)
                .tabular_nums()
                .text_color(color::INK),
        )
        .child(
            text(format!(".{fraction}"))
                .typo(Type::Title)
                .tabular_nums()
                .text_color(color::MUTED),
        )
}
