//! Dated valuation rates never rewrite recorded amounts.
use crate::{
    data::{clock, finance, market, tasks},
    domain::meal::Day,
    i18n::statement_import::copy,
    nav,
    ui::{
        Btn, Type, Typo, color,
        field::{field, text_input},
        sheet::{retained, task_sheet},
        space,
        surface::row_button,
    },
};
use navi_finance::{
    currency::{self, Currency, FxRate},
    holdings,
};
use nsh_core::{element::Screen, prelude::*};

pub fn page() -> Screen {
    let edit = signal(None::<Currency>);
    nsh_base::nav_page().header_visible(false).status_bar(super::parts::status_bar)
        .child(view().flex_1().bg(color::CANVAS)
            .child(super::parts::top_bar(|| copy("Exchange rates", "汇率").into(), nav::pop, None))
            .child(scroll().flex_1().child(view().px(px(space::GUTTER)).gap_4()
                .child(text(|| copy("Assets are valued in CNY. Dated rates do not change recorded amounts.", "资产总览折算为人民币。汇率按日期保存，不改变已记录的原币金额。")).typo(Type::Subhead).text_color(color::MUTED))
                .child(Btn::secondary().label(|| copy("Refresh prices and rates", "刷新价格与汇率").into()).busy(|| market::status().refreshing).on_press(||{tasks::spawn_app(market::refresh(true));}))
                .child(when(||market::status().failed>0,||text(||copy("Some updates failed. Previous dates and rates are retained; you can enter a rate below.","部分更新失败，保留原价格、汇率及日期，也可在下方手动填写。")).typo(Type::Body).text_color(color::MUTED)))
                .children([Currency::HKD, Currency::USD].into_iter().map(move |c|{
                    row_button(move||edit.set(Some(c))).px_0().py_4().child(view().gap_2()
                        .child(text(move||format!("{} → CNY",c.code())).typo(Type::Headline).text_color(color::INK))
                        .child(text(move||currency::rate_in(&finance::rates(),c,clock::today().0).map(|r|format!("1 {} = {} CNY · {} · {}",c.code(),holdings::format_units(r.rate),r.day,if r.source=="manual"{copy("Manual","手动")}else{r.source.as_str()})).unwrap_or_else(||copy("Missing rate · tap to enter", "缺少汇率 · 点按填写").into())).typo(Type::Subhead).text_color(color::MUTED)))
                }))))
            .child(retained(move||edit.get(),move|currency|{
                untracked(move||{
                    let value=signal(String::new());let date=signal(clock::today().to_string());let calendar=signal(false);let error=signal(false);
                    let asking=signal(false);
                    let close=move||{
                        if calendar.get_untracked(){calendar.set(false);return}
                        if value.get_untracked().trim().is_empty(){edit.set(None);return}
                        if asking.get_untracked(){return} asking.set(true);
                        let answer=nsh_base::alert_dialog().title(crate::i18n::s().discard_title).description(crate::i18n::s().finance_discard_body).cancel("keep",crate::i18n::s().keep_editing).destructive("discard",crate::i18n::s().discard).show();
                        tasks::spawn_app(async move{let discard=answer.await.is_ok_and(|a|a.action.as_deref()==Some("discard"));asking.try_set(false);if discard{edit.try_set(None);}});
                    };
                    task_sheet(move||edit.get().is_some(),close,
                        view().flex_row().items_center().child(text(format!("1 {} → CNY",currency.code())).typo(Type::Title).flex_1()).child(Btn::ghost().label(||copy("Cancel","取消").into()).on_press(close)),
                        view().gap_3().child(when(move||calendar.get(),move||super::finance::date_picker(date,move||calendar.set(false))).otherwise(move||view().gap_3()
                            .child(field(||copy("CNY per unit", "每单位折合人民币"),text_input(value).label(||copy("CNY per unit", "每单位折合人民币")).keyboard_type(KeyboardType::Decimal)))
                            .child(Btn::ghost().label(move||date.get().into()).on_press(move||calendar.set(true)))))
                            .child(when(move||error.get(),||text(||copy("Check the positive rate and date, then try again.","请检查汇率与日期后重试。")).typo(Type::Body).text_color(color::DANGER))),
                        Btn::primary().label(||copy("Save rate","保存汇率").into()).on_press(move||{
                            let Some(rate)=holdings::parse_units(&value.get_untracked()).filter(|r|*r>0) else{error.set(true);return};
                            let Ok(day)=date.get_untracked().parse::<Day>() else{error.set(true);return};
                            if day>clock::today(){error.set(true);return}
                            if finance::save_rate(FxRate{currency,day:day.0,rate,source:"manual".into()}).is_ok(){edit.set(None)}else{error.set(true)}
                        })
                    ).into_element()
                })
            })))
}
