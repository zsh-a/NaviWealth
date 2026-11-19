//! Favorites: saving a meal, logging it again with one tap (and Undo),
//! removing it in Edit (and Undo), and keeping it across a restart and the
//! deletion of the meal it came from.

mod common;

use common::*;

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
    app.wait_for("Nothing recorded today")?;

    app.press(OPEN)?;
    app.wait_for("text:Favorites")?;
    app.wait_for("text:Edit")?;
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
    app.wait_for("Nothing recorded today")?;
    assert!(stored_meals(dir.path()).is_empty());
    drop(app);

    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press(OPEN)?;
    app.wait_for(TILE)?;
    Ok(())
}

#[test]
fn edit_removes_a_favorite_with_undo_and_no_long_press() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    save_pasta(&mut app)?;
    app.press("label:Back")?;
    app.wait_for(OPEN)?;

    app.press(OPEN)?;
    app.wait_for(TILE)?;
    assert!(!app.shows("text:Tap to log · Hold for more"));
    app.press("text:Edit")?;
    app.wait_for("text:Done")?;
    // In Edit a tap removes instead of logging.
    app.press("id:favorites >> label:Remove from favorites, Tomato pasta")?;
    app.wait_for("Removed from favorites")?;
    assert!(stored_favorites(dir.path()).is_empty());
    assert_eq!(stored_meals(dir.path()).len(), 1);

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

#[test]
fn failed_favorite_writes_preserve_the_bookmark_and_allow_retry() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    let dialogs = storage_dialogs(&mut app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_favorite BEFORE INSERT ON saved_meals BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press("Tomato pasta")?;
    app.press("label:Save as favorite")?;
    assert_eq!(dialogs.load(std::sync::atomic::Ordering::Relaxed), 1);
    assert!(stored_favorites(dir.path()).is_empty());
    app.wait_for("label:Save as favorite")?;
    db.execute_batch("DROP TRIGGER reject_favorite").unwrap();
    app.press("label:Save as favorite")?;
    app.wait_for("label:Remove from favorites")?;
    db.execute_batch("CREATE TRIGGER reject_remove BEFORE DELETE ON saved_meals BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press("label:Remove from favorites")?;
    assert_eq!(dialogs.load(std::sync::atomic::Ordering::Relaxed), 2);
    assert_eq!(stored_favorites(dir.path()).len(), 1);
    app.wait_for("label:Remove from favorites")?;
    db.execute_batch("DROP TRIGGER reject_remove").unwrap();
    app.press("label:Remove from favorites")?;
    app.wait_for("label:Save as favorite")?;
    assert!(stored_favorites(dir.path()).is_empty());
    Ok(())
}

#[test]
fn logging_a_favorite_rolls_back_the_meal_when_last_use_cannot_commit() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    save_pasta(&mut app)?;
    let before = stored_favorites(dir.path());
    app.press("label:Back")?;
    let dialogs = storage_dialogs(&mut app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_last_use BEFORE UPDATE ON saved_meals BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press(OPEN)?;
    app.press(TILE)?;
    assert_eq!(dialogs.load(std::sync::atomic::Ordering::Relaxed), 1);
    assert_eq!(stored_meals(dir.path()).len(), 1);
    assert_eq!(stored_favorites(dir.path()), before);
    app.wait_for(TILE)?;
    db.execute_batch("DROP TRIGGER reject_last_use").unwrap();
    app.press(TILE)?;
    app.wait_for("Logged Tomato pasta")?;
    app.wait_for("text:2 meals")?;
    assert_eq!(stored_meals(dir.path()).len(), 2);
    Ok(())
}
