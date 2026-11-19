use super::*;

fn profile() -> UserProfile {
    UserProfile {
        height_cm: 170,
        age_years: 23,
        sex: Sex::Male,
    }
}
// Public reference test captures, retained as wire evidence rather than code.
fn weight() -> Vec<u8> {
    hex("AC298068E2C2020005400000000000000029D511")
}
fn adc() -> Vec<u8> {
    hex("AC290200020501D8018068E2C20000000029D60E")
}
fn hex(input: &str) -> Vec<u8> {
    input
        .as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}
fn checksum(mut bytes: Vec<u8>) -> Vec<u8> {
    bytes[19] = bytes[2..19].iter().fold(0u8, |sum, n| sum.wrapping_add(*n)) & 0x1f;
    bytes
}

#[test]
fn attributed_live_fixtures_keep_original_grams_and_primary_adc() {
    let mut protocol = Protocol;
    assert_eq!(
        protocol.feed(&weight()).unwrap(),
        Some(Event::Weight {
            weight_grams: 58050,
            stable: true
        })
    );
    assert_eq!(
        protocol.feed(&adc()).unwrap(),
        Some(Event::Impedance {
            weight_grams: 58050,
            raw_impedances: vec![517.0, 472.0]
        })
    );
    let mut session = Session::new(profile()).unwrap();
    let stable = session.feed(&weight()).unwrap().unwrap();
    assert_eq!(stable.weight_kg(), 58.05);
    assert!(stable.metrics.is_none());
    assert!(stable.valid());
    let reading = session.feed(&adc()).unwrap().unwrap();
    assert_eq!(reading.resistance_ohm, Some(517.0));
    assert_eq!(
        reading.metrics,
        bodycomp::estimate(58.05, 170.0, 23, Sex::Male, Some(517.0))
    );
    assert!(reading.valid());
    assert_eq!(
        serde_json::from_str::<Measurement>(&serde_json::to_string(&reading).unwrap()).unwrap(),
        reading
    );
    assert!(
        session.feed(&adc()).unwrap().is_none(),
        "duplicate notification does not create another draft"
    );
    assert!(
        session.feed(&weight()).unwrap().is_none(),
        "late identical stable notification does not lose valid composition"
    );
}

#[test]
fn empty_or_unusable_adc_does_not_replace_composition_within_a_load_cycle() {
    let mut session = Session::new(profile()).unwrap();
    session.feed(&weight()).unwrap();
    let complete = session.feed(&adc()).unwrap().unwrap();
    for primary in [0_u16, 99, 65535] {
        let mut empty = adc();
        empty[4..6].copy_from_slice(&primary.to_be_bytes());
        assert!(session.feed(&checksum(empty)).unwrap().is_none());
        assert_eq!(session.latest(), Some(complete.clone()));
    }

    let mut moving = weight();
    moving[2] &= 0x7f;
    assert!(session.feed(&checksum(moving)).unwrap().is_none());
    assert!(session.latest().is_none());
    session.feed(&weight()).unwrap();
    let mut empty = adc();
    empty[4..8].fill(0);
    let incomplete = session.feed(&checksum(empty)).unwrap().unwrap();
    assert!(incomplete.metrics.is_none());
    assert_eq!(incomplete.raw_impedances, vec![0.0, 0.0]);
    assert!(incomplete.valid());
}

#[test]
fn changed_usable_resistance_reaches_host_when_original_model_cannot_estimate_it() {
    for original_algorithm in [Algorithm::Wu2015, Algorithm::Sun2003] {
        let mut session = Session::with_algorithm(profile(), original_algorithm).unwrap();
        session.feed(&weight()).unwrap();
        let first = session.feed(&adc()).unwrap().unwrap();
        assert!(first.metrics.is_some());
        // The host changes its selected algorithm without changing BLE/session
        // state. Its draft is normalized from the original model's evidence.
        let previous_host_draft = first.reestimate(Algorithm::Segal).unwrap();
        let mut changed = adc();
        changed[4..6].copy_from_slice(&100_u16.to_be_bytes());
        let changed = checksum(changed);
        let evidence = session.feed(&changed).unwrap().unwrap();
        assert_eq!(evidence.algorithm(), Some(original_algorithm));
        assert_eq!(evidence.weight_grams, 58_050);
        assert_eq!(evidence.resistance_ohm, Some(100.0));
        assert_eq!(evidence.raw_impedances, vec![100.0, 472.0]);
        assert!(evidence.metrics.is_none());
        assert!(evidence.valid());
        assert_eq!(session.latest(), Some(evidence.clone()));
        let next_host_draft = evidence.reestimate(Algorithm::Segal).unwrap();
        assert_eq!(next_host_draft.resistance_ohm, Some(100.0));
        assert!(next_host_draft.metrics.is_some());
        assert_ne!(next_host_draft.metrics, previous_host_draft.metrics);
        assert_ne!(next_host_draft, previous_host_draft);
        assert!(next_host_draft.valid());
        assert!(session.live_reading().unwrap().stable);
        assert!(session.feed(&changed).unwrap().is_none());
        assert!(session.feed(&weight()).unwrap().is_none());
        assert_eq!(session.latest(), Some(evidence));
    }
}

#[test]
fn unusable_resistance_cannot_erase_host_composition_when_original_model_has_none() {
    for original_algorithm in [Algorithm::Wu2015, Algorithm::Sun2003] {
        let mut session = Session::with_algorithm(profile(), original_algorithm).unwrap();
        session.feed(&weight()).unwrap();
        let mut usable = adc();
        usable[4..6].copy_from_slice(&100_u16.to_be_bytes());
        let usable = checksum(usable);
        let evidence = session.feed(&usable).unwrap().unwrap();
        assert!(evidence.metrics.is_none());
        assert_eq!(evidence.resistance_ohm, Some(100.0));
        let host_draft = evidence.reestimate(Algorithm::Segal).unwrap();
        assert!(host_draft.metrics.is_some());
        for primary in [0_u16, 99, 65_535] {
            let mut invalid = adc();
            invalid[4..6].copy_from_slice(&primary.to_be_bytes());
            assert!(session.feed(&checksum(invalid)).unwrap().is_none());
            let retained = session.latest().unwrap();
            assert_eq!(retained, evidence);
            assert!(retained.valid());
            assert_eq!(
                retained.reestimate(Algorithm::Segal),
                Some(host_draft.clone())
            );
        }
        // A new moving-weight cycle must discard the previous load's evidence.
        let mut moving = weight();
        moving[2] &= 0x7f;
        assert!(session.feed(&checksum(moving)).unwrap().is_none());
        assert!(session.latest().is_none());
        assert!(!session.live_reading().unwrap().stable);
        session.feed(&weight()).unwrap();
        let mut empty = adc();
        empty[4..8].fill(0);
        let incomplete = session.feed(&checksum(empty)).unwrap().unwrap();
        assert!(incomplete.resistance_ohm.is_none());
        assert!(incomplete.metrics.is_none());
        assert!(incomplete.valid());
        assert!(
            incomplete
                .reestimate(Algorithm::Segal)
                .unwrap()
                .metrics
                .is_none()
        );
    }
}

#[test]
fn dynamic_mismatched_and_out_of_order_readings_never_mix() {
    let mut session = Session::new(profile()).unwrap();
    assert_eq!(
        session.feed(&adc()).unwrap_err(),
        ScaleError::StaleMeasurement
    );
    let mut moving = weight();
    moving[2] &= 0x7f;
    let moving = checksum(moving);
    assert!(session.feed(&moving).unwrap().is_none());
    assert!(session.latest().is_none());
    assert_eq!(
        session.feed(&adc()).unwrap_err(),
        ScaleError::StaleMeasurement
    );
    session.feed(&weight()).unwrap();
    let mut changed = adc();
    changed[12] = changed[12].wrapping_add(1);
    assert_eq!(
        session.feed(&checksum(changed)).unwrap_err(),
        ScaleError::StaleMeasurement
    );
    assert!(session.latest().is_none());
    session.feed(&weight()).unwrap();
    session.reset();
    assert_eq!(
        session.feed(&adc()).unwrap_err(),
        ScaleError::StaleMeasurement
    );
}

#[test]
fn malformed_packets_reset_candidates_and_do_not_poison_the_next_frame() {
    let mut session = Session::new(profile()).unwrap();
    session.feed(&weight()).unwrap();
    let mut damaged = adc();
    damaged[4] ^= 1;
    assert_eq!(session.feed(&damaged).unwrap_err(), ScaleError::Checksum);
    assert!(session.latest().is_none());
    for length in [0, 1, 18, 19, 21, 40, 1024] {
        assert_eq!(
            session.feed(&vec![0xac; length]).unwrap_err(),
            ScaleError::Length
        );
    }
    for index in [0, 1] {
        let mut bad = weight();
        bad[index] = 0;
        assert_eq!(
            session.feed(&checksum(bad)).unwrap_err(),
            ScaleError::Packet
        );
    }
    for count in [0, 5, 6, 255] {
        let mut bad = adc();
        bad[2] = count;
        assert_eq!(
            session.feed(&checksum(bad)).unwrap_err(),
            ScaleError::Packet
        );
    }
    assert!(session.feed(&weight()).unwrap().unwrap().valid());
    assert!(session.feed(&adc()).unwrap().unwrap().valid());
}

#[test]
fn history_and_settings_cannot_be_saved_as_live_measurements() {
    let mut protocol = Protocol;
    for kind in [0xd8, 0xdf, 0xff] {
        let mut data = weight();
        data[18] = kind;
        assert_eq!(protocol.feed(&checksum(data)).unwrap(), None);
    }
}

#[test]
fn invalid_or_missing_primary_impedance_never_uses_bmi_as_body_fat() {
    for raw in [vec![], vec![0.0, 517.0], vec![99.0], vec![65535.0]] {
        let reading = measurement(58050, raw, &profile(), Algorithm::Segal);
        assert_eq!(reading.resistance_ohm, None);
        assert_eq!(reading.metrics, None);
        assert!(reading.valid());
    }
    let converted = measurement(58050, vec![4270.2], &profile(), Algorithm::Segal);
    assert_eq!(converted.resistance_ohm, Some(506.33));
    // Raw wire ADCs are integers: persisted fractional ADCs are not valid.
    assert!(!converted.valid());
    let reordered = measurement(
        58050,
        vec![200.0, 300.0, 400.0, 500.0, 506.0],
        &profile(),
        Algorithm::Segal,
    );
    assert_eq!(reordered.resistance_ohm, Some(506.0));
    assert!(reordered.valid());
}

#[test]
fn measurements_are_revalidated_from_their_profile_and_raw_evidence() {
    let mut session = Session::new(profile()).unwrap();
    session.feed(&weight()).unwrap();
    let good = session.feed(&adc()).unwrap().unwrap();
    let mut altered = good.clone();
    altered.metrics.as_mut().unwrap().body_fat_percent += 1.0;
    assert!(!altered.valid());
    let mut altered = good.clone();
    altered.resistance_ohm = Some(500.0);
    assert!(!altered.valid());
    let mut altered = good.clone();
    altered.profile.height_cm = 0;
    assert!(!altered.valid());
    let mut altered = good.clone();
    altered.algorithm_version = "other".into();
    assert!(!altered.valid());
    let mut altered = good;
    altered.raw_impedances = vec![f64::NAN];
    assert!(!altered.valid());
    assert!(
        Session::new(UserProfile {
            age_years: 0,
            ..profile()
        })
        .is_err()
    );
}

#[test]
fn legacy_json_remains_byte_for_byte_compatible_and_valid() {
    // Frozen pre-selection schema and values, independent of serialization
    // generated by the implementation under test. No new Measurement fields.
    let json = r#"{"weight_grams":58050,"resistance_ohm":517.0,"raw_impedances":[517.0,472.0],"metrics":{"body_fat_percent":11.8,"muscle_percent":83.7,"water_percent":61.7,"resistance_ohm":517.0,"model":"segal_3a_male_lt20"},"profile":{"height_cm":170,"age_years":23,"sex":"male"},"algorithm_version":"afu_wl_scale27_bia_v1"}"#;
    let reading: Measurement = serde_json::from_str(json).unwrap();
    assert_eq!(reading.algorithm(), Some(Algorithm::Segal));
    assert!(reading.valid());
    assert_eq!(serde_json::to_string(&reading).unwrap(), json);
    assert_eq!(reading.reestimate(Algorithm::Segal), Some(reading.clone()));
    let mut session = Session::new(profile()).unwrap();
    session.feed(&weight()).unwrap();
    assert_eq!(session.feed(&adc()).unwrap(), Some(reading));
}

#[test]
fn selected_sessions_and_explicit_reestimation_preserve_frozen_original_evidence() {
    let mut entered_profile = profile();
    let mut legacy = Session::new(entered_profile.clone()).unwrap();
    legacy.feed(&weight()).unwrap();
    let source = legacy.feed(&adc()).unwrap().unwrap();
    // Later profile edits must not reinterpret a session or historic reading.
    entered_profile.height_cm = 190;
    entered_profile.age_years = 45;
    entered_profile.sex = Sex::Female;
    for algorithm in Algorithm::ALL {
        let mut session = Session::with_algorithm(profile(), algorithm).unwrap();
        let weight_only = session.feed(&weight()).unwrap().unwrap();
        assert_eq!(weight_only.algorithm(), Some(algorithm));
        assert!(weight_only.valid());
        assert!(weight_only.metrics.is_none());
        assert!(weight_only.resistance_ohm.is_none());
        let reading = session.feed(&adc()).unwrap().unwrap();
        assert_eq!(source.reestimate(algorithm), Some(reading.clone()));
        assert_eq!(reading.weight_grams, 58_050);
        assert_eq!(reading.raw_impedances, vec![517.0, 472.0]);
        assert_eq!(reading.resistance_ohm, Some(517.0));
        assert_eq!(reading.profile, profile());
        assert_ne!(reading.profile, entered_profile);
        assert_eq!(reading.algorithm(), Some(algorithm));
        assert_eq!(
            Algorithm::from_model_id(&reading.metrics.as_ref().unwrap().model),
            Some(algorithm)
        );
        assert!(reading.valid());
        assert_eq!(reading.reestimate(Algorithm::Segal), Some(source.clone()));
        let restored: Measurement =
            serde_json::from_str(&serde_json::to_string(&reading).unwrap()).unwrap();
        assert_eq!(restored, reading);
        assert!(restored.valid());
        session.reset();
        assert!(session.latest().is_none());
        session.feed(&weight()).unwrap();
        assert_eq!(session.feed(&adc()).unwrap(), Some(reading));
    }
    assert_eq!(source.algorithm_version, ALGORITHM_VERSION);
    assert!(source.valid());
}

#[test]
fn exact_new_versions_reject_relabelling_and_tampering_before_reestimation() {
    for (algorithm, version) in [
        (Algorithm::Wu2015, "afu_wl_scale27_wu2015_ffm_v1"),
        (Algorithm::Sun2003, "afu_wl_scale27_sun2003_ffm_tbw_v1"),
    ] {
        let good = measurement(58_050, vec![517.0, 472.0], &profile(), algorithm);
        assert_eq!(good.algorithm_version, version);
        assert!(good.valid());
        let mut corruptions = Vec::new();
        for version in [ALGORITHM_VERSION, "unknown", "afu_wl_scale27_wu2015_ffm_v2"] {
            let mut reading = good.clone();
            reading.algorithm_version = version.into();
            corruptions.push(reading);
        }
        let mut reading = good.clone();
        reading.algorithm_version = algorithm_version(if algorithm == Algorithm::Wu2015 {
            Algorithm::Sun2003
        } else {
            Algorithm::Wu2015
        })
        .into();
        corruptions.push(reading);
        for field in ["fat", "water", "muscle", "resistance", "model", "absent"] {
            let mut reading = good.clone();
            let metrics = reading.metrics.as_mut().unwrap();
            match field {
                "fat" => metrics.body_fat_percent += 0.1,
                "water" => metrics.water_percent += 0.1,
                "muscle" => metrics.muscle_percent += 0.1,
                "resistance" => metrics.resistance_ohm = Some(500.0),
                "model" => metrics.model = "unrecognized".into(),
                _ => reading.metrics = None,
            }
            corruptions.push(reading);
        }
        for raw in [
            vec![517.5],
            vec![f64::NAN],
            vec![-1.0],
            vec![65_536.0],
            vec![517.0; 6],
        ] {
            let mut reading = good.clone();
            reading.raw_impedances = raw;
            corruptions.push(reading);
        }
        let mut reading = good.clone();
        reading.weight_grams = 0;
        corruptions.push(reading);
        let mut reading = good.clone();
        reading.profile.height_cm = 175;
        corruptions.push(reading);
        let mut reading = good;
        reading.resistance_ohm = Some(500.0);
        corruptions.push(reading);
        for reading in corruptions {
            assert!(!reading.valid());
            for selected in Algorithm::ALL {
                assert!(reading.reestimate(selected).is_none());
            }
        }
    }
}

#[test]
fn inapplicable_models_keep_stable_weight_and_proxy_without_fabricated_composition() {
    for (algorithm, age) in [(Algorithm::Wu2015, 76), (Algorithm::Sun2003, 95)] {
        let profile = UserProfile {
            age_years: age,
            ..profile()
        };
        let mut session = Session::with_algorithm(profile.clone(), algorithm).unwrap();
        // Selection must not allow ADC to make an unstable measurement stable.
        assert_eq!(
            session.feed(&adc()).unwrap_err(),
            ScaleError::StaleMeasurement
        );
        let mut moving = weight();
        moving[2] &= 0x7f;
        assert!(session.feed(&checksum(moving)).unwrap().is_none());
        assert!(!session.live_reading().unwrap().stable);
        assert!(session.latest().is_none());
        let stable = session.feed(&weight()).unwrap().unwrap();
        assert!(stable.metrics.is_none());
        let reading = session.feed(&adc()).unwrap().unwrap();
        assert_eq!(reading.weight_grams, 58_050);
        assert_eq!(reading.resistance_ohm, Some(517.0));
        assert_eq!(reading.raw_impedances, vec![517.0, 472.0]);
        assert_eq!(reading.profile, profile);
        assert!(reading.metrics.is_none());
        assert_eq!(reading.algorithm(), Some(algorithm));
        assert!(reading.valid());
        assert!(session.live_reading().unwrap().stable);
        assert_eq!(reading.reestimate(algorithm), Some(reading.clone()));
        let mut fabricated = reading.clone();
        fabricated.metrics = reading.reestimate(Algorithm::Segal).unwrap().metrics;
        assert!(fabricated.metrics.is_some());
        assert!(!fabricated.valid());
        assert!(fabricated.reestimate(Algorithm::Segal).is_none());
    }
    for algorithm in Algorithm::ALL {
        let reading = measurement(58_050, vec![], &profile(), algorithm);
        assert!(reading.valid());
        for selected in Algorithm::ALL {
            let result = reading.reestimate(selected).unwrap();
            assert!(result.metrics.is_none());
            assert!(result.resistance_ohm.is_none());
            assert!(result.valid());
        }
        assert_eq!(
            Session::with_algorithm(
                UserProfile {
                    height_cm: 0,
                    ..profile()
                },
                algorithm
            )
            .unwrap_err(),
            ScaleError::Profile
        );
    }
}

#[test]
fn advertisement_identification_requires_verified_manufacturer_bytes() {
    let payload = vec![1, 2, 3, 4, 5, 6, 2];
    let expected = DeviceProtocol {
        device_type: 0x27,
        protocol_ver: 2,
    };
    assert_eq!(
        identify_advertisement(&[(0x27ac, payload.clone())], "AFU-WL-TZ-A1", &[]).unwrap(),
        expected
    );
    for data in [
        vec![],
        vec![(0x27ac, vec![])],
        vec![(0xa7ac, payload.clone())],
        vec![(0x29ac, payload.clone())],
    ] {
        assert!(identify_advertisement(&data, "AFU-WL-TZ-A1", &[SERVICE_UUID.into()]).is_err());
    }
    assert!(identify_advertisement(&[(0x27ac, payload.clone())], "Other scale", &[]).is_err());
    let mut conflicting = payload.clone();
    conflicting[6] = 1;
    assert!(
        identify_advertisement(
            &[(0x27ac, payload), (0x27ac, conflicting)],
            "AFU-WL-TZ-A1",
            &[]
        )
        .is_err()
    );
}

#[test]
fn initialization_has_checked_profile_timestamp_timezone_and_full_byte_checksum() {
    let packet = encode_profile(&profile(), 0x12345678, 32, 0x27, 2).unwrap();
    assert_eq!(packet, hex("AC2712345678200001AA0000170100000300D0CA"));
    assert_eq!(
        &packet[..10],
        &[0xac, 0x27, 0x12, 0x34, 0x56, 0x78, 32, 0, 1, 170]
    );
    assert_eq!(&packet[10..19], &[0, 0, 23, 1, 0, 0, 3, 0, 0xd0]);
    assert_eq!(
        packet[19],
        packet[2..19].iter().fold(0u8, |s, n| s.wrapping_add(*n))
    );
    assert_eq!(
        encode_initialization(
            &profile(),
            0x12345678,
            32,
            &DeviceProtocol {
                device_type: 0x27,
                protocol_ver: 2,
            },
            "AFU-WL",
        )
        .unwrap(),
        vec![packet]
    );
    assert_eq!(
        encode_profile(&profile(), 0, -49, 0x27, 0).unwrap_err(),
        ScaleError::Initialization
    );
    assert_eq!(
        encode_profile(&profile(), 0, 57, 0x27, 0).unwrap_err(),
        ScaleError::Initialization
    );
    assert_eq!(
        encode_profile(&profile(), 0, 0, 0x29, 0).unwrap_err(),
        ScaleError::Initialization
    );
    assert_eq!(
        encode_profile(&profile(), 0, 0, 0x27, 3).unwrap_err(),
        ScaleError::Initialization
    );
    assert!(
        encode_profile(
            &UserProfile {
                height_cm: 300,
                ..profile()
            },
            0,
            0,
            0x27,
            0
        )
        .is_err()
    );
    let negative = encode_profile(&profile(), 0, -48, 0x27, 0).unwrap();
    assert_eq!(negative[6], 208);
}

#[test]
fn live_weight_is_available_without_creating_a_confirmable_measurement() {
    let mut session = Session::new(profile()).unwrap();
    let mut moving = weight();
    moving[2] &= 0x7f;
    assert!(session.feed(&checksum(moving)).unwrap().is_none());
    assert_eq!(
        session.live_reading(),
        Some(LiveReading {
            weight_grams: 58_050,
            stable: false
        })
    );
    assert!(session.latest().is_none());
    session.feed(&weight()).unwrap();
    assert_eq!(
        session.live_reading(),
        Some(LiveReading {
            weight_grams: 58_050,
            stable: true
        })
    );
    assert!(session.feed(&[0xac]).is_err());
    assert!(session.live_reading().is_none());
    assert!(session.latest().is_none());
}

#[test]
fn display_summary_uses_original_measurement_and_keeps_missing_composition_missing() {
    let mut session = Session::new(profile()).unwrap();
    let weight_only = session.feed(&weight()).unwrap().unwrap();
    assert_eq!(weight_only.summary().bmi, Some(20.09));
    assert_eq!(weight_only.summary().fat_mass_kg, None);
    assert_eq!(weight_only.summary().fat_free_mass_kg, None);
    assert_eq!(weight_only.summary().muscle_mass_kg, None);
    assert_eq!(weight_only.summary().water_mass_kg, None);
    let complete = session.feed(&adc()).unwrap().unwrap();
    let summary = complete.summary();
    assert_eq!(summary.fat_mass_kg, Some(6.85));
    assert_eq!(summary.fat_free_mass_kg, Some(51.2));
    assert_eq!(summary.muscle_mass_kg, Some(48.59));
    assert_eq!(summary.water_mass_kg, Some(35.82));
    assert_eq!(summary.bmi, Some(20.09));
    assert!(complete.valid());
}

#[test]
fn tz_a1_initialization_uses_only_the_captured_clock_command() {
    let identity = DeviceProtocol {
        device_type: 0x27,
        protocol_ver: 1,
    };
    let commands =
        encode_initialization(&profile(), 0x12345678, 32, &identity, "AFU-WL-TZ-A1").unwrap();
    assert_eq!(
        commands,
        vec![vec![
            0xac, 0x27, 0x08, 0x12, 0x34, 0x56, 0x78, 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xdf,
            0x1b,
        ]]
    );
    assert_eq!(
        encode_initialization(
            &profile(),
            0x12345678,
            32,
            &DeviceProtocol {
                protocol_ver: 3,
                ..identity
            },
            "AFU-WL-TZ-A1",
        ),
        Err(ScaleError::Initialization)
    );
}

#[test]
fn service_data_is_verified_with_the_same_bounded_metadata_rules() {
    let data = vec![(
        "000027ac-0000-1000-8000-00805f9b34fb".into(),
        vec![1, 2, 3, 4, 5, 6, 2],
    )];
    assert_eq!(
        identify_advertisement_with_service_data(&[], "AFU-WL-TZ-A1", &[], &data).unwrap(),
        DeviceProtocol {
            device_type: 0x27,
            protocol_ver: 2
        }
    );
    assert!(
        identify_advertisement_with_service_data(
            &[],
            "AFU-WL-TZ-A1",
            &[],
            &[("000027ac-not-a-BLE-uuid".into(), vec![1, 2, 3, 4, 5, 6, 2])]
        )
        .is_err()
    );
    let mut short = data.clone();
    short[0].0 = "27AC".into();
    assert_eq!(
        identify_advertisement_with_service_data(&[], "AFU-WL-TZ-A1", &[], &short)
            .unwrap()
            .protocol_ver,
        2
    );
}

#[test]
fn a_dynamic_zero_weight_is_progress_and_dynamic_adc_cannot_finish() {
    let mut session = Session::new(profile()).unwrap();
    let mut zero = weight();
    zero[2..6].fill(0);
    assert!(session.feed(&checksum(zero)).unwrap().is_none());
    session.feed(&weight()).unwrap();
    let mut moving = adc();
    moving[9] &= 0x7f;
    assert!(session.feed(&checksum(moving)).is_err());
    assert!(session.latest().is_none());
}
