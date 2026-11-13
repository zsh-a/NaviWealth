//! Favorites: saving a meal, logging it again with one tap (and Undo),
//! adjusting it before logging, removing it, and keeping it across a
//! restart and the deletion of the meal it came from.

mod common;

use common::*;
use nsh_testing::DialogAnswer;

const TILE: &str = "id:favorites >> label:Tomato pasta, 300 kcal";
const OPEN: &str = "label:New entry";

fn stored_favorites(dir: &Path) -> Vec<Value> {
    let connection = rusqlite::Connection::open(database_in(dir)).expect("the database opens");
    let mut statement = connection.prepare("SELECT body FROM saved_meals").unwrap();
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .map(|body| serde_json::from_str(&body.unwrap()).unwrap())
        .collect()
}

/// Saves today's pasta as a favorite from its page and goes back to Today.
fn save_pasta(app: &mut Headless) -> Result<(), String> {
    app.wait_for("text:300")?;
    app.press("Tomato pasta")?;
    app.wait_for("Edit meal")?;
    app.press("label:Save as favorite")?;
    app.wait_for("label:Remove from favorites")?;
    Ok(())
}

#[test]
fn a_favorite_outlives_its_meal_and_logs_with_one_tap() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    save_pasta(&mut app)?;
    let kept = stored_favorites(dir.path());
    assert_eq!(kept.len(), 1);
    assert_eq!(kept[0]["source_meal"], "m1");
    assert_eq!(kept[0]["foods"][0]["name"], "Pasta");

    // The meal goes; the favorite stays.
    app.press("label:Delete meal")?;
    app.wait_for("No meals logged today")?;

    app.press(OPEN)?;
    app.wait_for("text:Favorites")?;
    app.wait_for("text:Tap to log · Hold for more")?;
    app.press(TILE)?;
    app.wait_for("Logged Tomato pasta")?;
    app.wait_for("text:1 meal")?;
    let meals = stored_meals(dir.path());
    assert_eq!(meals.len(), 1);
    assert_ne!(meals[0]["id"], "m1", "a new meal");
    assert_eq!(meals[0]["day"], today().to_string());
    assert_eq!(meals[0]["foods"][0]["grams"], 300.0);
    assert_eq!(
        meals[0]["foods"][0]["source"]["fdc_id"], "168927",
        "the catalog source is kept: {meals:?}"
    );

    app.press("Undo")?;
    app.wait_for("No meals logged today")?;
    assert!(stored_meals(dir.path()).is_empty());
    drop(app);

    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press(OPEN)?;
    app.wait_for(TILE)?;
    Ok(())
}

#[test]
fn holding_a_favorite_adjusts_it_before_logging_or_removes_it() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    save_pasta(&mut app)?;
    app.press("label:Back")?;
    app.wait_for(OPEN)?;

    app.on_dialog(|_| DialogAnswer::Press("Adjust, then log".into()));
    app.press(OPEN)?;
    app.long_press(TILE)?;
    app.wait_for("New meal")?;
    app.press("text:/^Save meal/")?;
    app.wait_for("text:2 meals")?;
    app.wait_for("text:600")?;
    assert_eq!(stored_meals(dir.path()).len(), 2);

    app.on_dialog(|_| DialogAnswer::Press("Remove from favorites".into()));
    app.press(OPEN)?;
    app.long_press(TILE)?;
    app.wait_for("Removed from favorites")?;
    assert!(stored_favorites(dir.path()).is_empty());

    app.press("Undo")?;
    app.wait_for_gone("Removed from favorites", GONE)?;
    assert_eq!(stored_favorites(dir.path()).len(), 1);
    Ok(())
}

#[test]
fn a_favorite_can_be_removed_from_its_meal() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    save_pasta(&mut app)?;
    app.press("label:Remove from favorites")?;
    app.wait_for("label:Save as favorite")?;
    assert!(stored_favorites(dir.path()).is_empty());
    Ok(())
}
