//! The health review is reachable and steps through complete seven-day windows.
mod common;
use common::*;

#[test]
fn weekly_intake_uses_logged_days_and_past_weeks_stay_empty() -> Result<(), String> {
    let (mut app, _) = start(pasta_today(), None);
    app.press("label:Week in review")?;
    app.wait_for("text:300")?;
    app.wait_for("text:kcal a day on logged days · 1 of 7 days logged")?;
    assert!(!app.shows("label:Next week"));
    app.press("label:Previous week")?;
    app.wait_for("Nothing logged in these seven days.")?;
    app.press("label:Next week")?;
    app.wait_for("text:300")?;
    app.press("label:Back")?;
    app.wait_for("Tomato pasta")?;
    Ok(())
}

#[test]
fn an_empty_week_never_displays_zero_intake() -> Result<(), String> {
    let (mut app, _) = start(vec![], None);
    app.press("label:Week in review")?;
    app.wait_for("Nothing logged in these seven days.")?;
    assert!(!app.shows("text:0"));
    Ok(())
}
