use super::*;
use std::collections::BTreeMap;

#[derive(Clone, PartialEq)]
pub(super) struct Composition {
    pub(super) currency: String,
    pub(super) categories: Vec<(String, Decimal)>,
    pub(super) total: Decimal,
}
pub(super) async fn load(s: &Services, from: i64, until: i64) -> Result<Vec<Composition>, String> {
    let mut sums = BTreeMap::<String, BTreeMap<String, Decimal>>::new();
    let mut offset = 0;
    loop {
        let records = s
            .finance_records(
                RecordFilter {
                    from: Some(from),
                    until: Some(until),
                    kind: Some(RecordKind::Expense),
                    ..Default::default()
                },
                200,
                offset,
            )
            .await?;
        let count = records.len();
        for r in records {
            let v = sums
                .entry(r.currency)
                .or_default()
                .entry(r.category_name.unwrap_or_else(|| "其他支出".into()))
                .or_default();
            *v = v.checked_add(r.amount).ok_or("分类合计超出范围")?;
        }
        if count < 200 {
            break;
        }
        offset += count as i64;
    }
    sums.into_iter()
        .map(|(currency, categories)| {
            let mut categories: Vec<_> = categories.into_iter().collect();
            categories.sort_by_key(|a| std::cmp::Reverse(a.1));
            let total = categories
                .iter()
                .try_fold(Decimal::ZERO, |v, (_, a)| v.checked_add(*a))
                .ok_or_else(|| "分类合计超出范围".to_owned())?;
            Ok(Composition {
                currency,
                categories,
                total,
            })
        })
        .collect::<Result<Vec<_>, String>>()
}
pub(super) fn render(data: Signal<Vec<Composition>>) -> impl IntoElement {
    each(
        move || data.get(),
        |c: &Composition| c.currency.clone(),
        move |c: ReadSignal<Composition>, _| {
            let c = c.get();
            let total = c.total;
            let mut segments = view()
                .flex_row()
                .h(px(7.0))
                .gap(px(2.0))
                .rounded(px(3.0))
                .overflow_hidden();
            let mut legend = view().flex_row().flex_wrap().gap_3();
            for (index, (name, amount)) in c.categories.iter().take(3).enumerate() {
                let r = ui::ratio(*amount, total);
                segments = segments.child(view().w(relative(r)).h_full().bg(move || match index {
                    0 => theme().primary,
                    1 => fui::data_cash(),
                    _ => theme().muted_foreground,
                }));
                legend = legend.child(ui::quiet_text(format!("{name} {:.0}%", r * 100.0)));
            }
            let first = c
                .categories
                .iter()
                .take(3)
                .map(|(_, a)| *a)
                .sum::<Decimal>();
            segments = segments.child(view().flex_1().h_full().bg(move || theme().border));
            if first < total {
                legend = legend.child(ui::quiet_text(format!(
                    "其他 {:.0}%",
                    ui::ratio(total - first, total) * 100.0
                )));
            }
            view()
                .test_id("ledger-category-composition")
                .gap_2()
                .child(segments)
                .child(legend)
        },
    )
}
