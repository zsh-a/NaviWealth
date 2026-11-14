//! The Records tab and logging late: every day newest first with its total,
//! weight in day summaries, the filters, and a meal moved to yesterday from its
//! date chip.

mod common;

use common::*;
use nsh_app_naviwealth_health::domain::meal::decode_meals;

/// The day strip names a day by its full date ("Thursday, November 12").
fn long_date(day: Day) -> String {
    day.0.strftime("%A, %B %-d").to_string()
}

#[test]
fn a_meal_logged_late_lands_on_its_day_in_records() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    app.wait_for("text:300")?;

    app.press("label:New entry")?;
    app.press("label:Add manually")?;
    app.wait_for("text:e.g. Beef noodle soup")?;
    app.type_text("text:e.g. Beef noodle soup", "Rice")?;
    app.type_text("label:Amount eaten", "200")?;
    app.type_text("label:Energy", "130")?;
    app.press("Done")?;
    app.wait_for("text:Rice")?;
    // Today unless moved: the chip opens the last four weeks.
    app.press("label:/^Day, /")?;
    let yesterday = today().plus_days(-1);
    app.press(&format!("label:{}", long_date(yesterday)))?;
    app.wait_for("text:Yesterday")?;
    app.press("text:/^Save meal/")?;

    // Today keeps only today's meal.
    app.wait_for("text:1 meal")?;
    let kept = stored_meals(dir.path());
    let rice = kept
        .iter()
        .find(|m| m["foods"][0]["name"] == "Rice")
        .unwrap();
    assert_eq!(rice["day"], yesterday.to_string());

    app.press("label:Records")?;
    app.wait_for("text:300 kcal")?;
    app.wait_for("text:Yesterday")?;
    app.wait_for("text:260 kcal")?;
    app.wait_for("label:Rice, 260 kcal")?;
    Ok(())
}

#[test]
fn records_fold_weight_into_summary_and_weight_filter_opens_editor() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    app.press("text:Tap to log")?;
    app.type_text("label:Weight", "70")?;
    app.press("Save weight")?;
    app.wait_for("label:Weight, 70.0 kg")?;

    app.press("label:Records")?;
    app.wait_for("text:300 kcal")?;
    app.wait_for("text:70.0 kg")?;
    assert!(!app.shows("label:Weight, 70.0 kg"));
    app.wait_for("label:/^Edit weight, /")?;
    app.wait_for("label:Tomato pasta, 300 kcal")?;

    app.press("Weight")?;
    app.wait_for_gone("label:Tomato pasta, 300 kcal", GONE)?;
    app.wait_for("label:Weight, 70.0 kg")?;
    app.press("label:Weight, 70.0 kg")?;
    app.wait_for("Save weight")?;
    app.press("Save weight")?;

    app.press("Meals")?;
    app.wait_for("label:Tomato pasta, 300 kcal")?;
    app.wait_for_gone("label:Weight, 70.0 kg", GONE)?;

    // A row opens its record.
    app.press("label:Tomato pasta, 300 kcal")?;
    app.wait_for("Edit meal")?;
    Ok(())
}

#[test]
fn records_without_any_entry_say_so() -> Result<(), String> {
    let (mut app, _) = start(Vec::new(), None);
    app.press("label:Records")?;
    app.wait_for("Nothing recorded yet")?;
    Ok(())
}

#[test]
fn weight_only_day_has_a_summary_that_opens_its_editor() -> Result<(), String> {
    let (mut app, _) = start(Vec::new(), None);
    app.press("text:Tap to log")?;
    app.type_text("label:Weight", "72.9")?;
    app.press("Save weight")?;
    app.press("label:Records")?;
    app.wait_for("text:72.9 kg")?;
    assert!(!app.shows("label:Weight, 72.9 kg"));
    app.press("label:/^Edit weight, /")?;
    app.wait_for("Save weight")?;
    app.press("Delete")?;
    app.wait_for("Nothing recorded yet")?;
    Ok(())
}

/// One 300 kcal pasta lunch on each of the last `days` days.
fn pasta_every_day(days: i32) -> Vec<(String, String)> {
    let template = decode_meals(&pasta_today()[0].1);
    let meals: Vec<Meal> = (0..days)
        .map(|back| Meal {
            id: format!("m{back}"),
            day: today().plus_days(-back),
            ..template[0].clone()
        })
        .collect();
    vec![("meals.v1".to_owned(), encode_meals(&meals))]
}

#[test]
fn the_calendar_goes_to_a_day_beyond_the_first_page() -> Result<(), String> {
    let (mut app, _) = start(pasta_every_day(40), None);
    app.press("label:Records")?;
    let target = today().plus_days(-35);
    assert!(!app.shows(&format!("text:{}", long_date(target))));

    app.press("label:Go to a day")?;
    app.wait_for("text:Go to a day")?;
    let months_back = (today().0.year() as i32 * 12 + today().0.month() as i32)
        - (target.0.year() as i32 * 12 + target.0.month() as i32);
    for _ in 0..months_back {
        app.press("label:Previous month")?;
    }
    app.press(&format!("label:{}, 300 kcal", long_date(target)))?;
    app.wait_for_gone("text:Go to a day", GONE)?;
    app.wait_for(&format!("text:{}", long_date(target)))?;
    Ok(())
}
