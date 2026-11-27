//! Read-only Review calculations for the assistant. Totals use complete local
//! snapshots; only the explanatory category/holding lists are bounded.
use std::collections::BTreeMap;

use navi_assistant::ToolSpec;
use navi_finance::{
    attribution::{self, Outcome},
    currency::{self, Currency, FxRate},
    holdings::Book,
    journal::Transaction,
    review as financial_review,
};
use navi_health::{
    garmin::GarminDay,
    meal::{Day, DaySummary},
    review::{self, Period, WeekStart},
    weight::records::{self as weight, Weight},
};
use serde_json::{Value, json};

use super::{
    clock, finance, garmin,
    market::{PriceSource, PriceSources},
    meals, weights,
};

const DETAIL_LIMIT: usize = 20;
const OUTPUT_LIMIT: usize = 48_000;

pub fn specs() -> Vec<ToolSpec> {
    [
        ("summarize_finances", "Domain-calculated income, spending and category changes by native currency, plus CNY net-worth attribution. Uses ALL confirmed records, not a page. Dates and missing rates are explicit; categories are bounded. For a calendar month/week use period and back (0=current, 1=previous). Otherwise supply both from/to, compared to the preceding equal-length interval. No future dates."),
        ("summarize_health", "Domain-calculated nutrition averages over logged days, seven-day weight trend and Garmin averages. Missing days are unknown, never zero. Compares calendar month/week (period and back) or an explicit from/to range with its predecessor. Uses all confirmed records; no future dates."),
    ].into_iter().map(|(name, description)| ToolSpec {
        name: name.into(), description: description.into(),
        parameters: json!({"type":"object","additionalProperties":false,"properties":{
            "period":{"type":"string","enum":["week","month"],"description":"Defaults to month; cannot combine with from/to."},
            "back":{"type":"integer","minimum":0,"maximum":120,"description":"Completed calendar periods ago; only with period or the default month."},
            "from":{"type":"string","description":"Inclusive YYYY-MM-DD; requires to, at most 366 days."},
            "to":{"type":"string","description":"Inclusive YYYY-MM-DD; requires from."}
        }})
    }).collect()
}

pub fn execute(name: &str, args: &Value) -> Option<Result<Value, String>> {
    if !matches!(name, "summarize_finances" | "summarize_health") {
        return None;
    }
    Some((|| {
        let spans = Spans::parse(args, clock::today(), crate::i18n::s().week_start())?;
        let result = if name == "summarize_finances" {
            finances(
                &finance::transactions_snapshot(),
                &finance::holdings_snapshot(),
                &finance::rates_snapshot(),
                spans,
                Some(&PriceSources::current()),
            )?
        } else {
            let weights = weights::all();
            json!({
                "source":"confirmed local meals, weights and imported Garmin observations; navi-health Review calculations",
                "current":health(spans.current, &weights, meals::summary, garmin::on),
                "previous":health(spans.previous, &weights, meals::summary, garmin::on),
                "comparison_basis":spans.basis,
                "missing_data":"Unlogged days are unknown, not zero. Averages describe recorded days, not all intake or activity. Weight trends require at least three measurements in each trailing seven-day window."
            })
        };
        if result.to_string().len() > OUTPUT_LIMIT {
            return Err("analysis_output_limit".into());
        }
        Ok(result)
    })())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Span {
    from: Day,
    to: Day,
}
impl Span {
    fn days(self) -> i32 {
        self.to.days_since(self.from) + 1
    }
    fn contains(self, day: Day) -> bool {
        day >= self.from && day <= self.to
    }
    fn json(self) -> Value {
        json!({"from":self.from,"to":self.to,"calendar_days":self.days()})
    }
}

#[derive(Clone, Copy, Debug)]
struct Spans {
    current: Span,
    previous: Span,
    basis: &'static str,
}

fn shift(day: Day, days: i32) -> Result<Day, String> {
    day.0
        .checked_add(jiff::Span::new().days(days))
        .map(Day)
        .map_err(|_| "invalid_date".into())
}

impl Spans {
    fn parse(args: &Value, today: Day, week_start: WeekStart) -> Result<Self, String> {
        let object = args.as_object().ok_or("invalid_tool_arguments")?;
        if object
            .keys()
            .any(|key| !["period", "back", "from", "to"].contains(&key.as_str()))
        {
            return Err("invalid_tool_arguments".into());
        }
        if object.contains_key("from") || object.contains_key("to") {
            if object.contains_key("period") || object.contains_key("back") {
                return Err("invalid_tool_arguments".into());
            }
            let date = |key| -> Result<Day, String> {
                args.get(key)
                    .and_then(Value::as_str)
                    .ok_or("invalid_date")?
                    .parse()
                    .map_err(|_| "invalid_date".into())
            };
            let current = Span {
                from: date("from")?,
                to: date("to")?,
            };
            if current.from > current.to || current.days() > 366 || current.to > today {
                return Err("date_range_limit".into());
            }
            let previous = Span {
                from: shift(current.from, -current.days())?,
                to: shift(current.from, -1)?,
            };
            return Ok(Self {
                current,
                previous,
                basis: "preceding equal-length inclusive interval",
            });
        }
        let period = match args.get("period") {
            None => Period::Month,
            Some(Value::String(s)) if s == "month" => Period::Month,
            Some(Value::String(s)) if s == "week" => Period::Week,
            _ => return Err("invalid_tool_arguments".into()),
        };
        let back = match args.get("back") {
            None => 0,
            Some(value) => value
                .as_u64()
                .filter(|&v| v <= 120)
                .ok_or("invalid_tool_arguments")? as i32,
        };
        let current_days = review::period_days_starting(period, today, back, week_start);
        let previous_days = review::period_days_starting(period, today, back + 1, week_start);
        let current = Span {
            from: current_days[0],
            to: *current_days.last().ok_or("invalid_date")?,
        };
        let full_end = match period {
            Period::Month => current.from.0.last_of_month(),
            Period::Week => shift(current.from, 6)?.0,
        };
        let previous = Span {
            from: previous_days[0],
            to: Day(financial_review::comparison_end(
                current.from.0,
                full_end,
                previous_days[0].0,
                previous_days.last().ok_or("invalid_date")?.0,
                today.0,
            )),
        };
        // Explicitly reject arithmetic boundaries instead of accepting Day's
        // saturating convenience behavior at the limits of the calendar.
        if previous.to >= current.from || previous.from > previous.to {
            return Err("invalid_date".into());
        }
        Ok(Self {
            current,
            previous,
            basis: "Review calendar periods; current partial period compares equal elapsed days, completed periods compare their full predecessor",
        })
    }
}

fn finances(
    entries: &[Transaction],
    book: &Book,
    rates: &[FxRate],
    spans: Spans,
    price_sources: Option<&PriceSources>,
) -> Result<Value, String> {
    let currencies: Vec<_> = Currency::ALL.into_iter().map(|currency| {
        let spending = |span: Span| financial_review::spending_in(entries, span.from.0, span.to.0, currency);
        let income = |span: Span| financial_review::income_in(entries, span.from.0, span.to.0, currency);
        let (current, previous) = (spending(spans.current), spending(spans.previous));
        let (earned, before) = (income(spans.current), income(spans.previous));
        json!({
            "currency":currency.code(),
            "spending":flow(current.total, current.records, &current.categories, previous.total, previous.records, &previous.categories),
            "income":flow(earned.total, earned.records, &earned.categories, before.total, before.records, &before.categories)
        })
    }).collect();
    Ok(json!({
        "source":"complete confirmed local journal; navi-finance Review and attribution calculations",
        "current":spans.current.json(),"previous":spans.previous.json(),"comparison_basis":spans.basis,
        "currencies":currencies,
        "net_worth":net_worth(entries, book, rates, spans.current, price_sources)?,
        "money_format":"exact integer minor units as strings; native currency totals are never added across currencies",
        "interpretation":"Totals describe recorded postings, not proof that all activity was recorded. Refunds reduce spending; income reversals reduce income. Category changes explain recorded differences, not their real-world cause. Income/spending account totals can include investment postings; net-worth attribution puts investment effects in its investment contribution."
    }))
}

fn flow(
    current: i64,
    current_records: usize,
    current_categories: &[(String, i64)],
    previous: i64,
    previous_records: usize,
    previous_categories: &[(String, i64)],
) -> Value {
    let mut categories = BTreeMap::<&str, (i64, i64)>::new();
    for (name, value) in current_categories {
        categories.entry(name).or_default().0 = *value;
    }
    for (name, value) in previous_categories {
        categories.entry(name).or_default().1 = *value;
    }
    let category_count = categories.len();
    let mut categories: Vec<_> = categories.into_iter().collect();
    categories.sort_by(|(a, (ac, ap)), (b, (bc, bp))| {
        (i128::from(*bc) - i128::from(*bp))
            .abs()
            .cmp(&(i128::from(*ac) - i128::from(*ap)).abs())
            .then(a.cmp(b))
    });
    let categories: Vec<_> = categories.into_iter().take(DETAIL_LIMIT).map(|(account,(now,before))| json!({
        "account":account,"current_minor_units":now.to_string(),"previous_minor_units":before.to_string(),
        "change_minor_units":(i128::from(now)-i128::from(before)).to_string()
    })).collect();
    json!({
        "current_minor_units":current.to_string(),"current_records":current_records,
        "previous_minor_units":previous.to_string(),"previous_records":previous_records,
        "change_minor_units":(current_records > 0 && previous_records > 0).then(|| (i128::from(current)-i128::from(previous)).to_string()),
        "comparison_available":current_records > 0 && previous_records > 0,
        "categories":categories,"category_count":category_count,"omitted_categories":category_count.saturating_sub(DETAIL_LIMIT),
        "detail_order":"largest absolute recorded category change first; missing category postings mean recorded zero, not proof of no activity"
    })
}

fn net_worth(
    entries: &[Transaction],
    book: &Book,
    rates: &[FxRate],
    span: Span,
    price_sources: Option<&PriceSources>,
) -> Result<Value, String> {
    let start = shift(span.from, -1)?;
    if !entries.iter().any(|t| t.at.date() <= span.to.0) {
        return Ok(json!({"status":"no_records","start_close":start,"end_close":span.to}));
    }
    let outcome = attribution::attribute(book, entries, rates, start.0, span.to.0)
        .map_err(|_| "analysis_unavailable")?;
    let mut result = match outcome {
        Outcome::Missing(missing) => {
            json!({"status":"missing_rates","missing_currencies":missing.iter().map(|c|c.code()).collect::<Vec<_>>()})
        }
        Outcome::Complete(a) => json!({
            "status":"complete","currency":"CNY","start_minor_units":a.start.to_string(),"end_minor_units":a.end.to_string(),"change_minor_units":a.change().to_string(),
            "contributions_minor_units":{"income":a.income.to_string(),"spending":a.spending.to_string(),"investment":a.investment.to_string(),"openings":a.openings.to_string(),"adjustments":a.adjustments.to_string(),"exchange":a.exchange.to_string()},
            "investment_by_security":a.holdings.iter().take(DETAIL_LIMIT).map(|(id,amount)|json!({"security":id,"contribution_minor_units":amount.to_string()})).collect::<Vec<_>>(),
            "omitted_holdings":a.holdings.len().saturating_sub(DETAIL_LIMIT)
        }),
    };
    result["start_close"] = json!(start);
    result["end_close"] = json!(span.to);
    result["valuation_basis"] = json!(
        "Local effective dated prices and rates at each close; holdings without a price use cost. These are recalculated values, not immutable historical snapshots. Contributions sum exactly; spending is normally negative."
    );
    result["rates"] = json!([start, span.to].into_iter().map(|day| json!({
        "as_of":day,"observations":Currency::ALL.into_iter().filter(|c|*c != Currency::CNY).map(|currency| {
            let rate = currency::rate_in(rates, currency, day.0);
            json!({"currency":currency.code(),"day":rate.as_ref().map(|r|r.day.to_string()),"cny_millionths":rate.as_ref().map(|r|r.rate.to_string()),"source":rate.as_ref().map(|r|r.source.as_str())})
        }).collect::<Vec<_>>()
    })).collect::<Vec<_>>());
    let mut prices = Vec::new();
    for day in [start, span.to] {
        let mut active = Vec::new();
        let mut fallback = 0;
        let mut count = 0usize;
        for security in &book.securities {
            let position = book
                .position(security, day.0)
                .map_err(|_| "analysis_unavailable")?;
            if position.quantity == 0 {
                continue;
            }
            count += 1;
            fallback += usize::from(position.value.is_none());
            if active.len() < DETAIL_LIMIT {
                active.push(json!({"security":security.id,"quote_day":position.quote.as_ref().map(|q|q.day.to_string()),"cost_fallback":position.value.is_none(),"source":price_source_json(position.quote.as_ref().and_then(|q|price_sources.and_then(|s|s.source(q))))}));
            }
        }
        prices.push(json!({"as_of":day,"active_holdings":count,"cost_fallback_count":fallback,"prices":active,"omitted_holdings":count.saturating_sub(DETAIL_LIMIT)}));
    }
    result["price_basis"] = json!(prices);
    Ok(result)
}

fn price_source_json(source: Option<PriceSource>) -> Value {
    match source {
        Some(PriceSource::Manual) => json!({"kind":"manual"}),
        Some(PriceSource::Close(provider)) => json!({"kind":"daily_close","provider":provider}),
        Some(PriceSource::Sampled {
            observed_at,
            previous_close,
        }) => {
            json!({"kind":"sampled","observed_at":observed_at.to_string(),"previous_close_only":previous_close})
        }
        None => json!({"kind":"unknown"}),
    }
}

fn health(
    span: Span,
    weights: &[Weight],
    summary: impl Fn(Day) -> DaySummary,
    garmin_on: impl Fn(Day) -> Option<GarminDay>,
) -> Value {
    let days: Vec<_> = (0..span.days())
        .map(|offset| span.from.plus_days(offset))
        .collect();
    let summaries: Vec<_> = days.iter().copied().map(summary).collect();
    let intake = review::intake(&summaries);
    let measured: Vec<_> = days.iter().copied().filter_map(garmin_on).collect();
    let recovery = review::recovery(&measured);
    let recorded_weights = weights.iter().filter(|w| span.contains(w.day)).count();
    json!({
        "range":span.json(),
        "nutrition":{"logged_days":intake.logged_days,"unknown_days":span.days() as usize-intake.logged_days,"meal_records":summaries.iter().map(|s|s.meals).sum::<usize>(),"average_per_logged_day":intake.average.map(|n|json!({"kcal":n.kcal,"protein_g":n.protein,"carbs_g":n.carbs,"fat_g":n.fat}))},
        "weight":{"recorded_days":recorded_weights,"start_trend_kg":weight::trend_weight(weights,span.from),"end_trend_kg":weight::trend_weight(weights,span.to),"trend_change_kg":review::weight_change(weights,span.from,span.to),"basis":"trailing seven-day means at each endpoint, including measurements before the requested range"},
        "garmin":{"measured_days":recovery.days,"average_sleep_seconds":recovery.sleep_seconds,"average_sleep_score":recovery.sleep_score,"average_resting_hr_bpm":recovery.resting_hr,"average_hrv_ms":recovery.hrv_ms,"average_steps":recovery.steps,"basis":"each metric averages only days with that metric"}
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use navi_finance::{
        account::{Account, AccountKind},
        journal::{Posting, Source},
    };
    use navi_health::nutrition::Nutrients;

    fn day(value: &str) -> Day {
        value.parse().unwrap()
    }
    fn spans(args: Value, today: &str) -> Spans {
        Spans::parse(&args, day(today), WeekStart::Monday).unwrap()
    }
    fn entry(id: usize, date: &str, currency: Currency, amount: i64) -> Transaction {
        Transaction {
            id: format!("e{id}"),
            at: format!("{date}T12:00:00").parse().unwrap(),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
            postings: vec![
                Posting {
                    account: Account::new_in(AccountKind::Expenses, "Food", currency).unwrap(),
                    amount,
                },
                Posting {
                    account: Account::new_in(AccountKind::Assets, "Cash", currency).unwrap(),
                    amount: -amount,
                },
            ],
        }
    }

    #[test]
    fn calendar_comparisons_match_review_partial_and_completed_months_and_locale_weeks() {
        let current = spans(json!({}), "2026-11-15");
        assert_eq!(
            current.current,
            Span {
                from: day("2026-11-01"),
                to: day("2026-11-15")
            }
        );
        assert_eq!(
            current.previous,
            Span {
                from: day("2026-10-01"),
                to: day("2026-10-15")
            }
        );
        let completed = spans(json!({"period":"month","back":1}), "2024-03-10");
        assert_eq!(completed.current.days(), 29);
        assert_eq!(completed.previous.days(), 31);
        let sunday = Spans::parse(
            &json!({"period":"week"}),
            day("2026-11-10"),
            WeekStart::Sunday,
        )
        .unwrap();
        assert_eq!(
            sunday.current,
            Span {
                from: day("2026-11-08"),
                to: day("2026-11-10")
            }
        );
        assert_eq!(
            sunday.previous,
            Span {
                from: day("2026-11-01"),
                to: day("2026-11-03")
            }
        );
    }

    #[test]
    fn explicit_spans_are_bounded_and_never_silently_ignore_conflicting_arguments() {
        let valid = spans(json!({"from":"2024-01-01","to":"2024-12-31"}), "2026-11-27");
        assert_eq!(valid.current.days(), 366);
        assert_eq!(valid.previous.to, day("2023-12-31"));
        for args in [
            json!({"from":"2024-01-01","to":"2025-01-01"}),
            json!({"from":"2026-11-28","to":"2026-11-28"}),
            json!({"from":"2026-11-01"}),
            json!({"from":"2026-11-01","to":"2026-11-02","period":"month"}),
            json!({"from":"2026-11-01","to":"2026-11-02","back":0}),
            json!({"back":-1}),
            json!({"back":121}),
            json!({"back":0.5}),
            json!({"period":null}),
            json!({"offset":10}),
        ] {
            assert!(
                Spans::parse(&args, day("2026-11-27"), WeekStart::Monday).is_err(),
                "{args}"
            );
        }
    }

    #[test]
    fn finance_totals_include_more_than_fifty_rows_and_refunds_without_mixing_currencies() {
        let range = spans(json!({"period":"month"}), "2026-11-27");
        let mut entries: Vec<_> = (0..75)
            .map(|id| entry(id, "2026-11-15", Currency::CNY, 101))
            .collect();
        entries.push(entry(75, "2026-11-15", Currency::CNY, -100));
        entries.push(entry(76, "2026-10-27", Currency::CNY, 300));
        entries.push(entry(77, "2026-10-28", Currency::CNY, 9000)); // outside matched previous span
        entries.push(entry(78, "2026-11-15", Currency::USD, 500));
        entries.push(entry(79, "2026-11-28", Currency::CNY, 8000)); // future relative to the request
        let result = finances(&entries, &Book::default(), &[], range, None).unwrap();
        assert_eq!(
            result["currencies"][0]["spending"]["current_minor_units"],
            "7475"
        );
        assert_eq!(result["currencies"][0]["spending"]["current_records"], 76);
        assert_eq!(
            result["currencies"][0]["spending"]["previous_minor_units"],
            "300"
        );
        assert_eq!(
            result["currencies"][0]["spending"]["change_minor_units"],
            "7175"
        );
        assert_eq!(
            result["currencies"][2]["spending"]["current_minor_units"],
            "500"
        );
        assert_eq!(
            result["currencies"][2]["spending"]["change_minor_units"],
            Value::Null
        );
        assert_eq!(result["net_worth"]["status"], "missing_rates");
        assert_eq!(result["net_worth"]["missing_currencies"], json!(["USD"]));
        assert!(result["net_worth"].get("change_minor_units").is_none());
    }

    #[test]
    fn net_worth_contributions_match_review_and_names_are_only_bounded_in_details() {
        let range = spans(json!({"from":"2026-11-01","to":"2026-11-02"}), "2026-11-27");
        let entries = vec![entry(0, "2026-11-01", Currency::CNY, 3500)];
        let result = finances(&entries, &Book::default(), &[], range, None).unwrap();
        assert_eq!(result["net_worth"]["status"], "complete");
        assert_eq!(result["net_worth"]["start_close"], "2026-10-31");
        assert_eq!(result["net_worth"]["change_minor_units"], "-3500");
        assert_eq!(
            result["net_worth"]["contributions_minor_units"]["spending"],
            "-3500"
        );
        let categories: Vec<_> = (0..30).map(|n| (format!("category{n}"), 100)).collect();
        let result = flow(3000, 30, &categories, 0, 0, &[]);
        assert_eq!(result["current_minor_units"], "3000");
        assert_eq!(result["categories"].as_array().unwrap().len(), DETAIL_LIMIT);
        assert_eq!(result["omitted_categories"], 10);
    }

    #[test]
    fn health_averages_exclude_missing_days_and_weight_uses_pre_period_history() {
        let span = Span {
            from: day("2026-11-01"),
            to: day("2026-11-14"),
        };
        let first = day("2026-10-26");
        let weights: Vec<_> = (0..20)
            .map(|d| Weight {
                day: first.plus_days(d),
                kg: 80.0 - f64::from(d) * 0.1,
                logged_at_ms: 0,
            })
            .collect();
        let result = health(
            span,
            &weights,
            |day| {
                if day == span.from {
                    DaySummary {
                        meals: 2,
                        total: Nutrients::new(1800.0, 90.0, 200.0, 60.0),
                    }
                } else {
                    DaySummary::default()
                }
            },
            |day| {
                (day == span.to).then(|| GarminDay {
                    steps: Some(5000),
                    ..Default::default()
                })
            },
        );
        assert_eq!(result["nutrition"]["logged_days"], 1);
        assert_eq!(result["nutrition"]["unknown_days"], 13);
        assert_eq!(
            result["nutrition"]["average_per_logged_day"]["kcal"],
            1800.0
        );
        assert_eq!(result["weight"]["trend_change_kg"], -1.3);
        assert_eq!(result["garmin"]["average_steps"], 5000.0);
        assert_eq!(result["garmin"]["average_resting_hr_bpm"], Value::Null);
        let empty = health(span, &[], |_| DaySummary::default(), |_| None);
        assert_eq!(empty["nutrition"]["average_per_logged_day"], Value::Null);
        assert_eq!(empty["weight"]["trend_change_kg"], Value::Null);
    }
}
