//! Body weight on Today: logging, checking, keeping and deleting.

mod common;

use common::*;

#[test]
fn todays_weight_is_logged_kept_and_checked() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("text:Tap to log")?;
    assert!(!app.shows("text:Connect"));
    assert!(!app.shows("text:Sleep"));
    assert!(!app.shows("text:Body Battery"));
    app.press("text:Tap to log")?;
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
    app.wait_for("label:Weight, 52.4 kg")?;
    assert_eq!(stored_weights(dir.path()), [(today().to_string(), 52.4)]);
    drop(app);

    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("label:Weight, 52.4 kg")?;
    Ok(())
}

#[test]
fn deleting_a_weight_can_be_undone() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("text:Tap to log")?;
    app.type_text("label:Weight", "70")?;
    app.press("Save weight")?;
    app.wait_for("label:Weight, 70.0 kg")?;
    app.press("label:Weight, 70.0 kg")?;
    app.press("Delete")?;
    app.wait_for("Weight deleted")?;
    assert!(stored_weights(dir.path()).is_empty());
    app.press("Undo")?;
    app.wait_for("label:Weight, 70.0 kg")?;
    assert_eq!(stored_weights(dir.path()).len(), 1);
    Ok(())
}

#[test]
fn today_and_review_use_the_shared_average_and_caption_fits_large_text() -> Result<(), String> {
    use nsh_core::{ApproxTextEngine, Points, Size, TextEngine};
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), Vec::new(), Some(garmin_cn()));
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    for back in 0..45 {
        db.execute(
            "INSERT INTO weights (day, kg, logged_at_ms) VALUES (?1, ?2, 0)",
            rusqlite::params![
                today().plus_days(-back).to_string(),
                70.0 + f64::from(back) * 0.1
            ],
        )
        .unwrap();
    }
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(garmin_cn()));
    app.set_viewport(Size::new(Points(360.0), Points(800.0)))?;
    app.set_environment("larger text", |e| e.font_scale = 1.3)?;
    app.wait_for("text:−0.7 · 7d")?;
    let nodes = app.screen().layout_nodes();
    let caption = nodes
        .iter()
        .find(|node| {
            node.text
                .as_ref()
                .is_some_and(|t| t.text.text.as_str() == "−0.7 · 7d")
        })
        .expect("the caption is laid out");
    assert!(caption.bounds.origin.x.0 >= 20.0);
    assert!(caption.bounds.origin.x.0 + caption.bounds.size.width.0 <= 340.0);
    assert!(
        caption.bounds.size.width.0 >= 280.0,
        "weight fills the disconnected row"
    );
    let content = caption.text.as_ref().unwrap();
    let measured = ApproxTextEngine.measure(&ApproxTextEngine.prepare(&content.text), None);
    assert!(
        measured.width.0 <= content.content.size.width.0,
        "the full caption fits"
    );
    assert!(caption.bounds.size.height.0 > 0.0);

    // The same caption must fit when Garmin uses the other two tiles.
    app.press("label:Settings")?;
    app.type_text("text:Paste your Garmin key", "GCDC-test-key")?;
    app.press("Connect")?;
    app.wait_for("text:Connected · garmin.cn")?;
    app.press("label:Back")?;
    app.wait_for("text:7h 32m")?;
    let nodes = app.screen().layout_nodes();
    let content = nodes
        .iter()
        .filter_map(|n| n.text.as_ref())
        .find(|t| t.text.text == "−0.7 · 7d")
        .unwrap();
    let mut full_text = (*content.text).clone();
    full_text.max_lines = 0;
    let measured = ApproxTextEngine.measure(
        &ApproxTextEngine.prepare(&full_text),
        Some(content.content.size.width),
    );
    assert!(
        measured.height.0 <= content.content.size.height.0 + 0.1,
        "caption fits without ellipsis with Garmin too"
    );

    app.press("label:Review")?;
    // The preceding complete calendar week spans six days between endpoints.
    app.press("label:Previous week")?;
    app.wait_for("text:−0.6 kg")?;
    app.wait_for("label:One sentence")?;
    app.press("label:Next week")?;
    assert!(!app.screen().enabled("label:Next week")?);
    app.press("This month")?;
    let delta = -f64::from(today().0.day() - 1) * 0.1;
    if delta != 0.0 {
        app.wait_for(&format!("text:−{:.1} kg", delta.abs()))?;
    }
    Ok(())
}
