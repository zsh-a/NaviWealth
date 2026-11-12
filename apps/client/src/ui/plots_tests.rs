use super::*;
#[test]
fn missing_valuations_split_official_plot_layers() {
    let p = vec![
        ("1".into(), Some(10.into())),
        ("2".into(), Some(20.into())),
        ("3".into(), None),
        ("4".into(), Some(30.into())),
        ("5".into(), Some(40.into())),
    ];
    let g = trend_geometry(&p);
    assert_eq!(g.segments.len(), 2);
    assert_eq!(g.segments[0].column("x").unwrap(), &[0.0, 1.0]);
    assert_eq!(g.segments[1].column("x").unwrap(), &[3.0, 4.0]);
    assert!(g.all.column("y").unwrap()[2].is_nan());
}
#[test]
fn geometry_preserves_cents_on_large_decimal_balances() {
    let lo: Decimal = "100000000000000000000.00".parse().unwrap();
    let hi: Decimal = "100000000000000000000.01".parse().unwrap();
    assert_eq!(position(lo, lo, hi), 0.0);
    assert_eq!(position(hi, lo, hi), 1.0);
}

#[component]
fn HoverPlot() -> impl IntoElement {
    view().child(
        trend_plot(
            vec![
                ("11-01".into(), Some(100.into())),
                ("11-02".into(), Some("100.01".parse().unwrap())),
                ("11-03".into(), Some(110.into())),
            ],
            "CNY".into(),
            false,
        )
        .w(px(300.0)),
    )
}
#[test]
fn official_plot_hover_shows_the_exact_decimal_readout() {
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    let mut config = EngineConfig::new(Root::of::<HoverPlot>());
    config.environment.os = nsh_core::platform::Os::Linux;
    config.environment.idiom = nsh_core::platform::Idiom::Desktop;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("id:finance-trend-plot").unwrap();
    app.hover("id:finance-trend-plot").unwrap();
    app.wait_for("text:11-02 · 100.01 CNY").unwrap();
}
