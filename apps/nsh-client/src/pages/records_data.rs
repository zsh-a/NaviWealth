use super::*;

pub(super) fn group(
    meals: Vec<Meal>,
    weights: Vec<Weight>,
    transactions: Vec<Transaction>,
    filter: Filter,
    zone: &jiff::tz::TimeZone,
) -> Vec<DayRecords> {
    let mut days: BTreeMap<Day, DayRecords> = BTreeMap::new();
    fn at(days: &mut BTreeMap<Day, DayRecords>, day: Day) -> &mut DayRecords {
        days.entry(day).or_insert_with(|| DayRecords {
            day,
            kcal: 0.0,
            meals: 0,
            weight: None,
            spending: None,
            foreign_spending: Vec::new(),
            entries: Vec::new(),
        })
    }
    if matches!(filter, Filter::All | Filter::Meals) {
        for meal in meals {
            let d = at(&mut days, meal.day);
            d.kcal += meal.total().kcal;
            d.meals += 1;
            d.entries.push(Entry::Meal(meal));
        }
    }
    if matches!(filter, Filter::All | Filter::Weight) {
        for w in weights {
            let day = at(&mut days, w.day);
            if filter == Filter::All {
                day.weight = Some(w);
            } else {
                day.entries.push(Entry::Weight(w));
            }
        }
    }
    if matches!(filter, Filter::All | Filter::Transactions) {
        for transaction in &transactions {
            at(&mut days, Day(transaction.at.date()))
                .entries
                .push(Entry::Transaction(transaction.clone()));
        }
        for day in days.values_mut() {
            if day
                .entries
                .iter()
                .any(|e| matches!(e, Entry::Transaction(_)))
            {
                day.foreign_spending = [
                    navi_finance::currency::Currency::HKD,
                    navi_finance::currency::Currency::USD,
                ]
                .into_iter()
                .filter_map(|currency| {
                    let spending = navi_finance::review::spending_in(
                        &transactions,
                        day.day.0,
                        day.day.0,
                        currency,
                    );
                    (spending.records > 0).then_some((currency, spending.total))
                })
                .collect();
                let cny = navi_finance::review::spending_in(
                    &transactions,
                    day.day.0,
                    day.day.0,
                    navi_finance::currency::Currency::CNY,
                );
                day.spending = (cny.records > 0).then_some(cny.total);
            }
        }
    }
    let at_time = |e: &Entry| match e {
        Entry::Meal(m) => local_time(m.logged_at_ms, zone),
        Entry::Weight(w) => local_time(w.logged_at_ms, zone),
        Entry::Transaction(t) => t.at.time(),
    };
    days.into_values()
        .rev()
        .map(|mut d| {
            d.entries.sort_by_key(|e| std::cmp::Reverse(at_time(e)));
            d
        })
        .collect()
}

fn local_time(ms: i64, zone: &jiff::tz::TimeZone) -> jiff::civil::Time {
    jiff::Timestamp::from_millisecond(ms)
        .unwrap_or(jiff::Timestamp::UNIX_EPOCH)
        .to_zoned(zone.clone())
        .time()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{
        meal::MealSlot,
        nutrition::{Food, FoodSource, Nutrients},
    };
    use navi_finance::journal;

    fn day(text: &str) -> Day {
        text.parse().unwrap()
    }

    fn meal(id: &str, on: &str, at: i64, kcal: f64) -> Meal {
        Meal {
            id: id.into(),
            day: day(on),
            logged_at_ms: at,
            slot: MealSlot::Lunch,
            title: None,
            foods: vec![Food {
                id: 1,
                name: "Rice".into(),
                grams: 100.0,
                per_100g: Nutrients::new(kcal, 1.0, 1.0, 1.0),
                source: FoodSource::Manual,
                confidence: None,
                estimated_grams: None,
            }],
            photo: None,
            model: None,
            prompt_version: None,
        }
    }

    fn weight(on: &str, kg: f64, at: i64) -> Weight {
        Weight {
            day: day(on),
            kg,
            logged_at_ms: at,
        }
    }

    #[test]
    fn all_folds_weights_into_headers_and_retains_weight_only_days() {
        let meals = vec![
            meal("a", "2026-11-12", 1, 300.0),
            meal("b", "2026-11-13", 3, 500.0),
            meal("c", "2026-11-13", 5, 200.0),
        ];
        let weights = vec![weight("2026-11-11", 68.9, 0), weight("2026-11-13", 68.4, 4)];
        let days = group(
            meals.clone(),
            weights.clone(),
            vec![],
            Filter::All,
            &jiff::tz::TimeZone::UTC,
        );
        assert_eq!(
            days.iter().map(|d| d.day.to_string()).collect::<Vec<_>>(),
            ["2026-11-13", "2026-11-12", "2026-11-11"]
        );
        assert_eq!((days[0].kcal, days[0].meals), (700.0, 2));
        assert!(matches!(&days[0].entries[0], Entry::Meal(m) if m.id == "c"));
        assert!(matches!(&days[0].entries[1], Entry::Meal(m) if m.id == "b"));
        assert_eq!(days[0].entries.len(), 2);
        assert_eq!(days[0].weight.unwrap().kg, 68.4);
        assert!(days[2].entries.is_empty());
        assert_eq!(days[2].weight.unwrap().kg, 68.9);

        assert_eq!(
            group(
                meals.clone(),
                weights.clone(),
                vec![],
                Filter::Meals,
                &jiff::tz::TimeZone::UTC
            )
            .len(),
            2
        );
        let only_weights = group(
            meals,
            weights,
            vec![],
            Filter::Weight,
            &jiff::tz::TimeZone::UTC,
        );
        assert_eq!(only_weights.len(), 2);
        assert_eq!(only_weights[0].meals, 0);
        assert!(only_weights[0].weight.is_none());
        assert!(matches!(only_weights[0].entries[0], Entry::Weight(w) if w.kg == 68.4));
        let only_meals = group(
            vec![meal("a", "2026-11-13", 1, 300.0)],
            vec![weight("2026-11-13", 72.0, 0)],
            vec![],
            Filter::Meals,
            &jiff::tz::TimeZone::UTC,
        );
        assert!(only_meals[0].weight.is_none());
    }
    #[test]
    fn non_spending_days_keep_transactions_without_a_spending_summary() {
        use navi_finance::{
            account::{Account, AccountKind},
            currency::Currency,
            journal::{Entry as JournalEntry, Source},
        };
        for currency in Currency::ALL {
            let cash = Account::new_in(AccountKind::Assets, "Cash", currency).unwrap();
            let card = Account::new_in(AccountKind::Liabilities, "Card", currency).unwrap();
            let entry = |id: &str| JournalEntry {
                id: id.into(),
                at: "2026-11-13T12:00:00".parse().unwrap(),
                payee: String::new(),
                note: String::new(),
                source: Source::Manual,
            };
            let transactions = vec![
                journal::opening(entry("opening"), &cash, 500000).unwrap(),
                journal::adjustment(entry("adjustment"), &cash, -200).unwrap(),
                journal::transfer(entry("transfer"), &cash, &card, 80000).unwrap(),
                journal::receive(
                    entry("income"),
                    &cash,
                    &Account::new_in(AccountKind::Income, "Salary", currency).unwrap(),
                    100000,
                )
                .unwrap(),
            ];
            for filter in [Filter::All, Filter::Transactions] {
                let days = group(
                    vec![],
                    vec![],
                    transactions.clone(),
                    filter,
                    &jiff::tz::TimeZone::UTC,
                );
                assert_eq!(days[0].entries.len(), 4);
                assert_eq!(days[0].spending, None);
                assert!(days[0].foreign_spending.is_empty());
            }
            // Expense records retain their native currency, including on a
            // day whose only other entry is a transfer.
            let mut transactions = transactions;
            transactions.push(
                journal::spend(
                    entry("expense"),
                    &cash,
                    &Account::new_in(AccountKind::Expenses, "Dining", currency).unwrap(),
                    3150,
                )
                .unwrap(),
            );
            let days = group(
                vec![],
                vec![],
                transactions,
                Filter::All,
                &jiff::tz::TimeZone::UTC,
            );
            if currency == Currency::CNY {
                assert_eq!(days[0].spending, Some(3150));
                assert!(days[0].foreign_spending.is_empty());
            } else {
                assert_eq!(days[0].spending, None);
                assert_eq!(days[0].foreign_spending, [(currency, 3150)]);
            }
        }
    }

    #[test]
    fn mixed_days_sort_by_local_time_and_only_expense_postings_count_as_spending() {
        use navi_finance::{
            account::{Account, AccountKind, defaults},
            journal::{Entry as JournalEntry, Source},
        };
        let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
        let card = Account::new(AccountKind::Liabilities, "Card").unwrap();
        let entry = |id: &str, at: &str| JournalEntry {
            id: id.into(),
            at: at.parse().unwrap(),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
        };
        let expense = journal::spend(
            entry("expense", "2026-11-13T12:00:00"),
            &cash,
            &defaults::expense("餐饮"),
            3150,
        )
        .unwrap();
        let income = journal::receive(
            entry("income", "2026-11-13T08:00:00"),
            &cash,
            &defaults::income("工资"),
            100000,
        )
        .unwrap();
        let transfer = journal::transfer(
            entry("transfer", "2026-11-13T17:00:00"),
            &cash,
            &card,
            80000,
        )
        .unwrap();
        // UTC 05:00 is 13:00 on this device, between expense and transfer.
        let meal_at = "2026-11-13T05:00:00Z"
            .parse::<jiff::Timestamp>()
            .unwrap()
            .as_millisecond();
        let meals = vec![meal("lunch", "2026-11-13", meal_at, 300.0)];
        let transactions = vec![expense, income, transfer];
        let zone = jiff::tz::TimeZone::fixed(jiff::tz::Offset::from_hours(8).unwrap());
        let all = group(
            meals.clone(),
            vec![],
            transactions.clone(),
            Filter::All,
            &zone,
        );
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].spending, Some(3150));
        assert!(matches!(&all[0].entries[0], Entry::Transaction(t) if t.id == "transfer"));
        assert!(matches!(&all[0].entries[1], Entry::Meal(m) if m.id == "lunch"));
        assert!(matches!(&all[0].entries[2], Entry::Transaction(t) if t.id == "expense"));
        let only = group(
            meals.clone(),
            vec![],
            transactions.clone(),
            Filter::Transactions,
            &zone,
        );
        assert_eq!(only[0].entries.len(), 3);
        assert_eq!(only[0].meals, 0);
        assert_eq!(only[0].spending, Some(3150));
        let meals_only = group(meals, vec![], transactions, Filter::Meals, &zone);
        assert_eq!(meals_only[0].spending, None);
        assert_eq!(meals_only[0].entries.len(), 1);
    }
}
