//! Locale-aligned calendar reviews, sparse intake and persistent notes.
mod common;
use common::*;

fn week_days() -> usize {
    ((today().0.weekday().to_monday_zero_offset() + 1) % 7 + 1) as usize
}

#[test]
fn weekly_intake_uses_logged_days_and_past_weeks_stay_empty() -> Result<(), String> {
    let (mut app, _) = start(pasta_today(), None);
    app.press("label:Review")?;
    app.wait_for("text:300")?;
    app.wait_for(&format!("text:1 of {} days logged", week_days()))?;
    assert!(!app.screen().enabled("label:Next week")?);
    app.press("label:Previous week")?;
    app.wait_for("Nothing logged in this period.")?;
    app.press("label:Next week")?;
    app.wait_for("text:300")?;
    app.press("label:Today")?;
    app.wait_for("Tomato pasta")?;
    Ok(())
}

#[test]
fn an_empty_week_never_displays_zero_intake() -> Result<(), String> {
    let (mut app, _) = start(vec![], None);
    app.press("label:Review")?;
    app.wait_for("Nothing logged in this period.")?;
    assert!(!app.shows("text:0"));
    Ok(())
}

#[test]
fn a_month_runs_from_its_first_day_and_steps_back_a_month() -> Result<(), String> {
    let (mut app, _) = start(pasta_today(), None);
    app.press("label:Review")?;
    app.press("Month")?;
    let days = today().0.day();
    app.wait_for(&format!("text:1 of {days} days logged"))?;
    app.wait_for("text:300")?;
    app.press("label:Previous month")?;
    app.wait_for("Nothing logged in this period.")?;
    app.press("label:Next month")?;
    app.wait_for("text:300")?;
    // Switching back shows the current week again.
    app.press("Week")?;
    app.wait_for(&format!("text:1 of {} days logged", week_days()))?;
    Ok(())
}

#[test]
fn sparse_logging_hides_the_over_goal_count() -> Result<(), String> {
    // 600 g of the 100 kcal pasta, past a 500 kcal goal.
    let meal = Meal {
        id: "m1".to_owned(),
        day: today(),
        logged_at_ms: jiff::Timestamp::now().as_millisecond(),
        slot: MealSlot::Dinner,
        title: Some("Big pasta".to_owned()),
        foods: vec![Food {
            id: 1,
            name: "Pasta".to_owned(),
            grams: 600.0,
            per_100g: Nutrients::new(100.0, 4.0, 20.0, 1.0),
            source: FoodSource::Manual,
            confidence: None,
            estimated_grams: None,
        }],
        photo: None,
        model: None,
        prompt_version: None,
    };
    let entries = vec![
        ("meals.v1".to_owned(), encode_meals(&[meal])),
        (
            "settings.v1".to_owned(),
            json!({ "goal_kcal": 500.0 }).to_string(),
        ),
    ];
    let (mut app, _) = start(entries, None);
    app.press("label:Review")?;
    app.wait_for("text:Goal 500")?;
    app.wait_for(&format!("text:1 of {} days logged", week_days()))?;
    assert!(!app.shows("text:/Goal 500 ·/"));
    app.press("Month")?;
    app.wait_for("text:/Goal 500 · 1 of .* days logged/")?;
    Ok(())
}

#[test]
fn a_note_survives_restart_and_stays_with_its_day() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), vec![], None);
    app.press("label:Review")?;
    app.type_text("label:One sentence", "Dinner was lighter.")?;
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let text: String = db
        .query_row(
            "SELECT text FROM review_notes WHERE day = ?1",
            [today().to_string()],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(text, "Dinner was lighter.");
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), vec![], None);
    app.press("label:Review")?;
    app.wait_for("Dinner was lighter.")?;
    app.press("label:Previous week")?;
    assert!(!app.shows("Dinner was lighter."));
    app.press("label:Next week")?;
    app.wait_for("Dinner was lighter.")?;
    Ok(())
}

#[test]
fn chinese_and_iso_reviews_start_monday() -> Result<(), String> {
    use nsh_core::platform::{Locale, LocaleSettings};
    let (mut app, _) = start(pasta_today(), None);
    for tag in ["zh-CN", "en-GB", "en"] {
        let locale = Locale::parse(tag).unwrap();
        app.set_environment("locale", |e| {
            e.locale = locale;
            e.locale_settings = LocaleSettings::of(locale);
        })?;
        app.press(if tag == "zh-CN" {
            "label:回顾"
        } else {
            "label:Review"
        })?;
        let logged = today().0.weekday().to_monday_zero_offset() + 1;
        app.wait_for(&if tag == "zh-CN" {
            format!("text:记录 1/{logged} 天")
        } else {
            format!("text:1 of {logged} days logged")
        })?;
    }
    Ok(())
}

#[test]
fn the_note_limit_matches_storage_and_failed_writes_can_be_retried() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), vec![], None);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_note BEFORE INSERT ON review_notes BEGIN SELECT RAISE(ABORT,'fixture refuses writes'); END;").unwrap();
    app.press("label:Review")?;
    let line = "记".repeat(279) + "😀";
    app.type_text("label:One sentence", &format!("{line}尾"))?;
    app.wait_for("280 / 280")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(!app.shows(&format!("{line}尾")));
    app.press("label:Previous week")?;
    app.press("label:Next week")?;
    app.wait_for(&line)?;
    db.execute("DROP TRIGGER reject_note", []).unwrap();
    app.press("Try again")?;
    let kept: String = db
        .query_row("SELECT text FROM review_notes", [], |r| r.get(0))
        .unwrap();
    assert_eq!(kept, line);
    assert!(!app.shows("Try again"));
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), vec![], None);
    app.press("label:Review")?;
    app.wait_for(&line)?;
    Ok(())
}
