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
    app.wait_for("label:/^Body metrics, 52.4 kg, /")?;
    assert_eq!(stored_weights(dir.path()), [(today().to_string(), 52.4)]);
    drop(app);

    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("label:/^Body metrics, 52.4 kg, /")?;
    Ok(())
}

#[test]
fn deleting_a_weight_can_be_undone() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("text:Tap to log")?;
    app.type_text("label:Weight", "70")?;
    app.press("Save weight")?;
    app.wait_for("label:/^Body metrics, 70.0 kg, /")?;
    app.press("label:/^Body metrics, 70.0 kg, /")?;
    app.press("Edit weight")?;
    app.press("Delete")?;
    app.wait_for("Weight deleted")?;
    assert!(stored_weights(dir.path()).is_empty());
    app.press("Undo")?;
    app.wait_for("label:/^Body metrics, 70.0 kg, /")?;
    assert_eq!(stored_weights(dir.path()).len(), 1);
    Ok(())
}

#[test]
fn today_and_review_use_the_shared_average_at_large_text() -> Result<(), String> {
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
    app.wait_for("text:↓0.7 kg · 7d")?;
    let nodes = app.screen().layout_nodes();
    let caption = nodes
        .iter()
        .find(|node| {
            node.text
                .as_ref()
                .is_some_and(|t| t.text.text.as_str() == "↓0.7 kg · 7d")
        })
        .expect("the caption is laid out");
    assert!(caption.bounds.origin.x.0 >= 20.0);
    assert!(caption.bounds.origin.x.0 + caption.bounds.size.width.0 <= 340.0);
    assert!(
        caption.bounds.size.width.0 >= 50.0,
        "the trend remains readable"
    );
    let content = caption.text.as_ref().unwrap();
    let measured = ApproxTextEngine.measure(&ApproxTextEngine.prepare(&content.text), None);
    assert!(
        measured.width.0 <= content.content.size.width.0,
        "the full caption fits"
    );
    assert!(caption.bounds.size.height.0 > 0.0);

    // Garmin has its own row and cannot shrink the body summary.
    app.press("label:Settings")?;
    app.press("label:/^Garmin, /")?;
    app.type_text("text:Paste your Garmin key", "GCDC-test-key")?;
    app.press("Connect")?;
    app.wait_for("text:Connected · garmin.cn")?;
    app.press("label:Back")?;
    app.wait_for("text:7h 32m")?;
    let nodes = app.screen().layout_nodes();
    let content = nodes
        .iter()
        .filter_map(|n| n.text.as_ref())
        .find(|t| t.text.text == "↓0.7 kg · 7d")
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
    // Review leads with what changed.
    app.wait_for("text:Weight fell 0.6 kg.")?;
    app.wait_for("label:One sentence")?;
    app.press("label:Next week")?;
    assert!(!app.screen().enabled("label:Next week")?);
    app.press("This month")?;
    let delta = -f64::from(today().0.day() - 1) * 0.1;
    if delta != 0.0 {
        app.wait_for(&format!("text:Weight fell {:.1} kg.", delta.abs()))?;
    }
    Ok(())
}

/// The scale context a seeded estimate carries: the Today caption, the
/// editor's read-only estimate and BMI, the Review charts and the Records
/// row.
#[test]
fn scale_context_shows_on_today_in_the_editor_in_review_and_records() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let profile = json!({"height_cm": 175, "age_years": 33, "sex": "male", "goal_kg": 72.0});
    let profile = vec![("settings.v1".to_owned(), profile.to_string())];
    let (app, _) = start_in(Some(dir.path()), profile.clone(), None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    for back in 0..10 {
        db.execute(
            "INSERT INTO weights (day, kg, logged_at_ms) VALUES (?1, ?2, 0)",
            rusqlite::params![
                today().plus_days(-back).to_string(),
                70.0 + f64::from(back) * 0.1
            ],
        )
        .unwrap();
    }
    for back in 0..3 {
        db.execute(
            "INSERT INTO body_metrics (day, body, fetched_at_ms) VALUES (?1, ?2, 0)",
            rusqlite::params![
                today().plus_days(-back).to_string(),
                json!({
                    "body_fat_percent": 18.3,
                    "muscle_percent": 76.9,
                    "water_percent": 56.9,
                    "resistance_ohm": 506.0,
                    "model": "segal_3a_male_lt20"
                })
                .to_string()
            ],
        )
        .unwrap();
    }
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), profile, None);

    // Today keeps three facts; goal context is disclosed in the overview.
    app.wait_for("text:/↓0\\.5 kg · 7d/")?;
    app.wait_for("text:18.3%")?;
    app.wait_for("text:22.9")?;

    // The overview exposes composition and the goal before manual editing.
    app.press("label:/^Body metrics, 70\\.0 kg/")?;
    app.wait_for("text:/\u{2212}2\\.0 kg to goal/")?;
    app.press("Edit weight")?;
    app.wait_for("Save weight")?;
    app.wait_for(
        "text:/Scale estimate \u{b7} Body fat 18\\.3% \u{b7} Muscle 76\\.9% \u{b7} Water 56\\.9%/",
    )?;
    app.wait_for("text:BMI 22.86")?;
    app.press("Save weight")?;

    app.press("label:Back")?;

    // Review: the longer window and the body-fat line.
    app.press("label:Review")?;
    app.wait_for("text:30 days")?;
    app.press("90 days")?;
    app.wait_for("text:Body fat")?;

    // Records: the weight row carries the estimate.
    app.press("label:Records")?;
    app.press("Weight")?;
    app.wait_for("label:/^Weight, 70\\.0 kg/")?;
    app.wait_for("text:/Body fat 18\\.3%/")?;
    Ok(())
}

/// A new manual weight cannot acquire yesterday's body composition.
#[test]
fn body_summary_joins_by_day_and_dates_old_measurements() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), Vec::new(), None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let yesterday = today().plus_days(-1).to_string();
    db.execute(
        "INSERT INTO weights (day,kg,logged_at_ms) VALUES (?1,70,0)",
        [&yesterday],
    )
    .unwrap();
    db.execute("INSERT INTO body_metrics (day,body,fetched_at_ms) VALUES (?1,?2,0)",
        rusqlite::params![yesterday, json!({"body_fat_percent":18.3,"muscle_percent":76.9,"water_percent":56.9,"resistance_ohm":506.0,"model":"segal_3a_male_lt20"}).to_string()]).unwrap();
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("label:/^Body metrics, 70.0 kg, /")?;
    app.wait_for("text:18.3%")?;
    app.press("label:/^Body metrics, 70.0 kg, /")?;
    app.wait_for("Log weight")?;
    let dates: Vec<_> = app
        .screen()
        .layout_nodes()
        .into_iter()
        .filter_map(|n| n.text)
        .filter(|t| {
            t.text
                .text
                .contains(&today().plus_days(-1).0.strftime("%B %-d").to_string())
        })
        .collect();
    assert!(
        !dates.is_empty(),
        "the kept measurement is explicitly dated"
    );
    app.press("Log weight")?;
    // Prefilled from yesterday; saving today keeps a manual weight only.
    app.press("Save weight")?;
    app.wait_for("text:Measure with your scale to add body composition.")?;
    assert!(!app.shows("text:18.3%"));
    assert!(!app.shows("Measurement details"));
    app.press("label:Back")?;
    app.wait_for("label:/^Body metrics, 70.0 kg, /")?;
    assert!(!app.shows("text:18.3%"));
    Ok(())
}

#[test]
fn longest_weight_never_squeezes_garmin_at_narrow_width_or_large_text() -> Result<(), String> {
    use nsh_core::{ApproxTextEngine, Points, Size, TextEngine};
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), Vec::new(), Some(garmin_cn()));
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute(
        "INSERT INTO weights (day,kg,logged_at_ms) VALUES (?1,400,0)",
        [today().to_string()],
    )
    .unwrap();
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(garmin_cn()));
    app.press("label:Settings")?;
    app.press("label:/^Garmin, /")?;
    app.type_text("text:Paste your Garmin key", "GCDC-test-key")?;
    app.press("Connect")?;
    app.wait_for("text:Connected · garmin.cn")?;
    app.press("label:Back")?;
    app.wait_for("text:7h 32m")?;
    for scale in [1.0, 1.3, 1.8] {
        app.set_viewport(Size::new(Points(320.0), Points(1000.0)))?;
        app.set_environment("font scale", |e| e.font_scale = scale)?;
        app.wait_for("label:/^Body metrics, 400.0 kg, /")?;
        let nodes = app.screen().layout_nodes();
        for test_id in ["body-summary", "garmin-vitals"] {
            let root = nodes
                .iter()
                .find(|n| n.test_id.as_deref() == Some(test_id))
                .unwrap();
            for node in nodes.iter().filter(|n| n.text.is_some() && !n.hidden) {
                let mut parent = node.parent;
                let mut inside = parent == root.id;
                while !inside {
                    let Some(ancestor) = nodes.iter().find(|n| n.id == parent) else {
                        break;
                    };
                    if ancestor.parent == parent {
                        break;
                    }
                    parent = ancestor.parent;
                    inside = parent == root.id;
                }
                if !inside {
                    continue;
                }
                assert!(
                    node.bounds.origin.x.0 >= 19.5
                        && node.bounds.origin.x.0 + node.bounds.size.width.0 <= 300.5,
                    "{test_id} at {scale}: {:?}",
                    node.bounds
                );
                let content = node.text.as_ref().unwrap();
                let mut written = (*content.text).clone();
                written.max_lines = 0;
                let measured = ApproxTextEngine.measure(
                    &ApproxTextEngine.prepare(&written),
                    Some(content.content.size.width),
                );
                assert!(
                    measured.height.0 <= content.content.size.height.0 + 0.5,
                    "{} fits at {scale}",
                    written.text
                );
            }
            if test_id == "garmin-vitals" && scale == 1.0 {
                let tiles: Vec<_> = nodes
                    .iter()
                    .filter(|n| n.parent == root.id && n.bounds.size.width.0 > 10.0)
                    .collect();
                assert_eq!(tiles.len(), 2);
                assert!((tiles[0].bounds.size.width.0 - tiles[1].bounds.size.width.0).abs() < 0.5);
            }
        }
    }
    Ok(())
}

#[test]
fn body_overview_uses_the_confirmed_measurements_frozen_profile_and_mass() -> Result<(), String> {
    use navi_health::{
        bodycomp::Sex,
        scale::{Session, UserProfile},
    };
    let dir = tempfile::tempdir().unwrap();
    // The current profile is different from the one used by this measurement.
    let settings = vec![(
        "settings.v1".into(),
        json!({"height_cm":180,"age_years":45,"sex":"female"}).to_string(),
    )];
    let (app, _) = start_in(Some(dir.path()), settings.clone(), None);
    drop(app);
    let mut protocol = Session::new(UserProfile {
        height_cm: 170,
        age_years: 23,
        sex: Sex::Male,
    })
    .unwrap();
    let decode = |hex: &str| {
        (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect::<Vec<_>>()
    };
    protocol
        .feed(&decode("AC298068E2C2020005400000000000000029D511"))
        .unwrap();
    let measurement = protocol
        .feed(&decode("AC290200020501D8018068E2C20000000029D60E"))
        .unwrap()
        .unwrap();
    assert!(measurement.valid());
    let expected = measurement.summary();
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let day = today().to_string();
    let session = "a".repeat(32);
    db.execute(
        "INSERT INTO weights(day,kg,logged_at_ms) VALUES(?1,58.1,1)",
        [&day],
    )
    .unwrap();
    db.execute(
        "INSERT INTO body_metrics(day,body,fetched_at_ms) VALUES(?1,?2,1)",
        rusqlite::params![
            day,
            serde_json::to_string(measurement.metrics.as_ref().unwrap()).unwrap()
        ],
    )
    .unwrap();
    let saved = json!({"preview":{"session_id":session,"token":"b".repeat(32),"day":day,"measured_at_ms":1,
        "device":{"id":"fixture-device","name":"AFU-WL-TZ-A1"},"measurement":measurement,"existing_kg":null},"confirmed_at_ms":2});
    db.execute(
        "INSERT INTO scale_measurements(day,session_id,body) VALUES(?1,?2,?3)",
        rusqlite::params![day, session, saved.to_string()],
    )
    .unwrap();
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), settings, None);
    app.wait_for(&format!("text:{:.1}", expected.bmi.unwrap()))?;
    app.press("label:/^Body metrics, 58.1 kg, /")?;
    app.press("Measurement details")?;
    app.wait_for("text:170 cm · Age 23")?;
    app.wait_for(&format!("text:{:.2} kg", expected.fat_mass_kg.unwrap()))?;
    app.wait_for(&format!("text:{:.2} kg", expected.water_mass_kg.unwrap()))?;
    app.press("Edit weight")?;
    app.wait_for("Save weight")?;
    app.wait_for(&format!("text:BMI {}", expected.bmi.unwrap()))?;
    app.set_viewport(nsh_core::Size::new(
        nsh_core::Points(320.0),
        nsh_core::Points(640.0),
    ))?;
    app.set_environment("large text and keyboard", |e| {
        e.font_scale = 1.8;
        e.keyboard_height = nsh_core::Points(240.0);
    })?;
    let actions = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some("task-actions"))
        .unwrap();
    assert!(actions.bounds.origin.y.0 >= 0.0);
    assert!(actions.bounds.origin.y.0 + actions.bounds.size.height.0 <= 400.5);
    for label in ["Delete", "Save weight"] {
        let node = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.text.as_ref().is_some_and(|t| t.text.text == label))
            .unwrap();
        assert!(
            node.bounds.origin.x.0 >= 19.5
                && node.bounds.origin.x.0 + node.bounds.size.width.0 <= 300.5
        );
    }
    app.set_environment("keyboard hidden", |e| {
        e.keyboard_height = nsh_core::Points(0.0);
        e.font_scale = 1.0;
    })?;
    app.press("label:Back")?;
    app.wait_for("Measurement details")?;
    app.press("label:Back")?;
    app.wait_for("label:/^Body metrics, 58.1 kg, /")?;
    assert_eq!(stored_weights(dir.path()), [(day, 58.1)]);
    drop(app);
    // Corrupt or stale same-day provenance is different from legacy data:
    // it must not be presented as this weight's composition.
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute("UPDATE weights SET kg=70", []).unwrap();
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("label:/^Body metrics, 70.0 kg, /")?;
    app.press("label:/^Body metrics, 70.0 kg, /")?;
    app.wait_for("text:Measure with your scale to add body composition.")?;
    assert!(!app.shows("Measurement details"));
    Ok(())
}
