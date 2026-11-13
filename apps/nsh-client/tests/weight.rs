//! Body weight on Today: logging, checking, keeping and deleting.

mod common;

use common::*;

#[test]
fn todays_weight_is_logged_kept_and_checked() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("text:Tap to log today's weight")?;
    app.press("text:Tap to log today's weight")?;
    app.wait_for("Save weight")?;
    app.type_text("label:Weight", "5")?;
    app.press("Save weight")?;
    app.wait_for("text:Enter a weight between 20 and 400 kg.")?;
    assert!(
        stored_weights(dir.path()).is_empty(),
        "nothing out of range is kept"
    );

    // Typing appends: the field now reads 52.44, kept to one decimal.
    app.type_text("label:Weight", "2.44")?;
    app.press("Save weight")?;
    app.wait_for("text:52.4")?;
    assert_eq!(stored_weights(dir.path()), [(today().to_string(), 52.4)]);
    drop(app);

    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("text:52.4")?;
    Ok(())
}

#[test]
fn deleting_a_weight_can_be_undone() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("text:Tap to log today's weight")?;
    app.type_text("label:Weight", "70")?;
    app.press("Save weight")?;
    app.wait_for("text:70.0")?;
    app.press("text:70.0")?;
    app.press("Delete")?;
    app.wait_for("Weight deleted")?;
    assert!(stored_weights(dir.path()).is_empty());
    app.press("Undo")?;
    app.wait_for("text:70.0")?;
    assert_eq!(stored_weights(dir.path()).len(), 1);
    Ok(())
}
