//! Recognition drafts: leaving the review page while the photo is read
//! keeps it as a draft on Today and in Records; it can be confirmed later,
//! discarded (with Undo), and survives a restart, where a recognition cut
//! short can be tried again with the kept photo.

mod common;

use common::*;

const READING: &str = "label:/^Reading your/";
const READY: &str = "label:/ is ready, /";

/// A model that answers after `delay`.
fn slow_network(delay: Duration) -> Arc<StubNetwork> {
    let mut answer = response(200, estimate());
    answer.delay = delay;
    Arc::new(StubNetwork::new([(MESSAGES.to_owned(), answer)]))
}

fn stored_drafts(dir: &Path) -> usize {
    let connection = rusqlite::Connection::open(database_in(dir)).expect("the database opens");
    connection
        .query_row("SELECT COUNT(*) FROM meal_drafts", [], |row| row.get(0))
        .unwrap()
}

/// Picks a photo, sends it (trusted account) and leaves the page at once.
fn leave_while_reading(app: &mut Headless) -> Result<(), String> {
    picks_a_photo(app);
    app.press("label:New entry")?;
    app.press("Log a meal")?;
    app.wait_for("label:Back")?;
    app.press("label:Back")?;
    app.wait_for("Kept on Today to confirm")?;
    Ok(())
}

#[test]
fn leaving_while_reading_keeps_a_draft_to_confirm_later() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let stub = slow_network(Duration::from_secs(4));
    let (mut app, _) = start_in(Some(dir.path()), account(true), Some(stub.clone()));
    leave_while_reading(&mut app)?;
    app.wait_for(READING)?;
    assert_eq!(stored_drafts(dir.path()), 1);
    assert!(
        app.shows("No meals logged today"),
        "a draft counts toward nothing"
    );

    // The recognition finishes with the page closed.
    app.wait_for(READY)?;
    assert_eq!(stub.requests().len(), 1);

    app.press("label:Records")?;
    app.wait_for("text:To confirm")?;
    app.press(READY)?;
    app.wait_for("text:White rice")?;
    app.press("text:/^Save meal/")?;
    app.wait_for_gone("text:To confirm", GONE)?;
    let meals = stored_meals(dir.path());
    assert_eq!(meals.len(), 1);
    assert_eq!(meals[0]["title"], "Beef noodle soup");
    let photo = meals[0]["photo"].as_str().unwrap().to_owned();
    assert!(
        photo.starts_with('d'),
        "the meal keeps the draft's photo: {photo}"
    );
    assert_eq!(stored_drafts(dir.path()), 0);
    Ok(())
}

#[test]
fn a_discarded_draft_can_be_brought_back() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let stub = slow_network(Duration::from_millis(300));
    let (mut app, _) = start_in(Some(dir.path()), account(true), Some(stub));
    leave_while_reading(&mut app)?;
    app.wait_for(READY)?;
    app.press(READY)?;
    app.press("label:Discard draft")?;
    app.wait_for("Draft discarded")?;
    app.wait_for_gone(READY, GONE)?;
    assert_eq!(stored_drafts(dir.path()), 0);
    app.press("Undo")?;
    app.wait_for(READY)?;
    assert_eq!(stored_drafts(dir.path()), 1);
    Ok(())
}

#[test]
fn a_recognition_cut_short_by_a_restart_can_be_tried_again() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(
        Some(dir.path()),
        account(true),
        Some(slow_network(Duration::from_secs(30))),
    );
    leave_while_reading(&mut app)?;
    app.wait_for(READING)?;
    drop(app);

    let stub = network(200, estimate());
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        Some(stub.clone()),
    );
    app.wait_for("label:/couldn't read the photo/")?;
    app.press("label:/couldn't read the photo/")?;
    app.press("Try again")?;
    app.wait_for("text:White rice")?;
    assert_eq!(stub.requests().len(), 1, "the kept photo is sent again");
    app.press("label:Back")?;
    app.wait_for(READY)?;
    Ok(())
}
