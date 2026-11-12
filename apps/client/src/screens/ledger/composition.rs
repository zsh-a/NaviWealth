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
            let mut parts = Vec::new();
            let mut legend = view().flex_row().flex_wrap().gap_3();
            for (name, amount) in c.categories.iter().take(3) {
                let r = ui::ratio(*amount, total);
                parts.push(*amount);
                legend = legend.child(ui::quiet_text(format!("{name} {:.0}%", r * 100.0)));
            }
            let first = c
                .categories
                .iter()
                .take(3)
                .map(|(_, a)| *a)
                .sum::<Decimal>();
            parts.push(total - first);
            if first < total {
                legend = legend.child(ui::quiet_text(format!(
                    "其他 {:.0}%",
                    ui::ratio(total - first, total) * 100.0
                )));
            }
            view()
                .test_id("ledger-category-composition")
                .gap_2()
                .child(ui::category_composition_plot(&parts, total))
                .child(legend)
        },
    )
}
