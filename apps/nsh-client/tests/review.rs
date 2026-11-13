//! The Review tab steps through complete seven-day windows.
mod common;
use common::*;

#[test]
fn weekly_intake_uses_logged_days_and_past_weeks_stay_empty() -> Result<(), String> {
    let (mut app, _) = start(pasta_today(), None);
    app.press("label:Review")?;
    app.wait_for("text:300")?;
    app.wait_for("text:1 of 7 days logged")?;
    assert!(!app.shows("label:Next week"));
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
    app.press("This month")?;
    let days = today().0.day();
    app.wait_for(&format!("text:1 of {days} days logged"))?;
    app.wait_for("text:300")?;
    app.press("label:Previous month")?;
    app.wait_for("Nothing logged in this period.")?;
    app.press("label:Next month")?;
    app.wait_for("text:300")?;
    // Switching back shows the current week again.
    app.press("This week")?;
    app.wait_for("text:1 of 7 days logged")?;
    Ok(())
}

#[test]
fn the_goal_marks_days_past_it() -> Result<(), String> {
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
    app.wait_for("text:Goal 500 · 1 over · 1 of 7 days logged")?;
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
