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
        let reading = measurement(58050, raw, &profile());
        assert_eq!(reading.resistance_ohm, None);
        assert_eq!(reading.metrics, None);
        assert!(reading.valid());
    }
    let converted = measurement(58050, vec![4270.2], &profile());
    assert_eq!(converted.resistance_ohm, Some(506.33));
    // Raw wire ADCs are integers: persisted fractional ADCs are not valid.
    assert!(!converted.valid());
    let reordered = measurement(58050, vec![200.0, 300.0, 400.0, 500.0, 506.0], &profile());
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
