//! Algorithm preferences must not reinterpret recorded body composition.
mod common;
use common::*;

#[test]
fn profile_algorithm_choice_is_kept_without_changing_the_body_profile() -> Result<(), String> {
    let (mut app, storage) = start(
        vec![(
            "settings.v1".into(),
            json!({
                "height_cm":170,"birth_date":"2000-01-01","sex":"male"
            })
            .to_string(),
        )],
        None,
    );
    app.set_viewport(nsh_core::Size::new(
        nsh_core::Points(390.0),
        nsh_core::Points(1800.0),
    ))?;
    app.press("label:Settings")?;
    app.press("label:Body profile, Complete")?;
    assert!(
        app.screen()
            .accessibility_state("label:Estimation algorithm, Segal BIA")?
            .selected
    );
    let range = "text:/^Ages 18–75/";
    assert!(!app.shows(range));
    app.press("Compare methods")?;
    app.wait_for(range)?;
    app.press("Compare methods")?;
    app.wait_for_gone(range, GONE)?;
    app.press("label:Estimation algorithm, Wu 2015")?;
    assert!(
        app.screen()
            .accessibility_state("label:Estimation algorithm, Wu 2015")?
            .selected
    );
    let kept: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
    assert_eq!(kept["scale_algorithm"], "wu2015");
    assert_eq!(kept["height_cm"], 170);
    assert_eq!(kept["birth_date"], "2000-01-01");
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start(entries, None);
    app.set_viewport(nsh_core::Size::new(
        nsh_core::Points(390.0),
        nsh_core::Points(1800.0),
    ))?;
    app.press("label:Settings")?;
    app.press("label:Body profile, Complete")?;
    assert!(
        app.screen()
            .accessibility_state("label:Estimation algorithm, Wu 2015")?
            .selected
    );
    Ok(())
}

#[test]
fn unknown_algorithm_preferences_do_not_discard_a_saved_body_profile() -> Result<(), String> {
    for algorithm in [json!("future_model"), json!(42), json!(null), json!([])] {
        let (mut app, _) = start(
            vec![("settings.v1".into(), json!({
            "height_cm":170,"birth_date":"2000-01-01","sex":"male","scale_algorithm":algorithm
        }).to_string())],
            None,
        );
        app.set_viewport(nsh_core::Size::new(
            nsh_core::Points(390.0),
            nsh_core::Points(1800.0),
        ))?;
        app.press("label:Settings")?;
        app.press("label:Body profile, Complete")?;
        assert_eq!(app.screen().input_text("label:Height")?, Some("170"));
        assert_eq!(
            app.screen().input_text("label:Birth date")?,
            Some("2000-01-01")
        );
        assert!(
            app.screen()
                .accessibility_state("label:Estimation algorithm, Segal BIA")?
                .selected
        );
    }
    Ok(())
}

#[test]
fn review_labels_each_algorithm_instead_of_joining_different_models() -> Result<(), String> {
    use navi_health::{
        bodycomp::{Algorithm, Sex},
        scale::{Session, UserProfile},
    };
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), Vec::new(), None);
    drop(app);
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let bytes = |hex: &str| {
        (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect::<Vec<_>>()
    };
    for (index, algorithm) in Algorithm::ALL.into_iter().enumerate() {
        let mut session = Session::with_algorithm(
            UserProfile {
                height_cm: 170,
                age_years: 23,
                sex: Sex::Male,
            },
            algorithm,
        )
        .unwrap();
        session
            .feed(&bytes("AC298068E2C2020005400000000000000029D511"))
            .unwrap();
        let measurement = session
            .feed(&bytes("AC290200020501D8018068E2C20000000029D60E"))
            .unwrap()
            .unwrap();
        let metrics = serde_json::to_string(measurement.metrics.as_ref().unwrap()).unwrap();
        for back in [index as i32, index as i32 + 7] {
            let day = today().plus_days(-back).to_string();
            c.execute(
                "INSERT INTO weights(day,kg,logged_at_ms) VALUES(?1,58.1,1)",
                [&day],
            )
            .unwrap();
            c.execute(
                "INSERT INTO body_metrics(day,body,fetched_at_ms) VALUES(?1,?2,1)",
                rusqlite::params![day, metrics],
            )
            .unwrap();
        }
    }
    drop(c);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Review")?;
    app.wait_for("text:Segal BIA")?;
    app.wait_for("text:Wu 2015")?;
    app.wait_for("text:Sun 2003")?;
    Ok(())
}
