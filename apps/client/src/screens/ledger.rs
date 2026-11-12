//! Finance workspace: dated activity, exact monthly totals, filtering and record management.
use crate::{
    finance::{FinanceRecord, RecordFilter, RecordKind, RecordSource},
    finance_ui as fui,
    state::Services,
    ui,
};
use chrono::{Datelike, Local, NaiveDate};
use naviwealth_finance::wealth::OperationKind;
use nsh_base::{SheetEvent, dialog, theme};
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::{cell::Cell, rc::Rc, sync::Arc};

fn month_window(offset: i32) -> (i64, i64, String) {
    month_window_for(Local::now().date_naive(), offset)
}
fn month_window_for(today: NaiveDate, offset: i32) -> (i64, i64, String) {
    let index = today.year() * 12 + today.month0() as i32 + offset;
    let year = index.div_euclid(12);
    let month = index.rem_euclid(12) as u32 + 1;
    let start = chrono::NaiveDate::from_ymd_opt(year, month, 1)
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc()
        .timestamp();
    let end = chrono::NaiveDate::from_ymd_opt(
        if month == 12 { year + 1 } else { year },
        if month == 12 { 1 } else { month + 1 },
        1,
    )
    .unwrap()
    .and_hms_opt(0, 0, 0)
    .unwrap()
    .and_utc()
    .timestamp();
    (start, end, format!("{year} 年 {month} 月"))
}
#[derive(Clone, PartialEq)]
struct Day {
    date: String,
    records: Vec<FinanceRecord>,
}
fn group_days(records: Vec<FinanceRecord>) -> Vec<Day> {
    let mut days: Vec<Day> = Vec::new();
    for record in records {
        let date = ui::ymd(record.date);
        if days.last().is_none_or(|d| d.date != date) {
            days.push(Day {
                date,
                records: Vec::new(),
            });
        }
        days.last_mut().unwrap().records.push(record);
    }
    days
}

// The repository deliberately bounds each page. Accumulate pages for the visible
// window so "load more" never treats that bound as the end of the user's history.
async fn visible_records(
    services: &Services,
    filter: RecordFilter,
    count: i64,
) -> Result<Vec<FinanceRecord>, String> {
    let mut records = Vec::new();
    while records.len() < count as usize {
        let take = (count - records.len() as i64).min(200);
        let page = services
            .finance_records(filter.clone(), take, records.len() as i64)
            .await?;
        let exhausted = page.len() < take as usize;
        records.extend(page);
        if exhausted {
            break;
        }
    }
    Ok(records)
}

#[path = "ledger/screen.rs"]
mod screen;
pub use screen::LedgerScreen;
#[path = "ledger/rows.rs"]
mod rows;
use rows::*;
#[path = "ledger/details.rs"]
mod details;
use details::record_detail;
pub use details::{capture_route, entry_route};
#[cfg(test)]
#[path = "ledger/tests.rs"]
mod calendar_tests;
#[path = "ledger/overlays.rs"]
mod overlays;

#[path = "ledger/budget.rs"]
mod budget;

#[path = "ledger/composition.rs"]
mod composition;

#[path = "ledger/shortcuts.rs"]
mod shortcuts;

#[path = "ledger/loading.rs"]
mod loading;
