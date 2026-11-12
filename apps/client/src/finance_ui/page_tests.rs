use super::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
#[component]
fn RootProbe() -> impl IntoElement {
    provide_context(PageKind::Root);
    page("Overview", text("根内容"))
}
#[component]
fn DetailProbe() -> impl IntoElement {
    provide_context(PageKind::Detail);
    page("财富", text("详情内容"))
}
#[test]
fn page_kind_controls_header_independently_of_title() {
    let mut root = Headless::start(EngineConfig::new(Root::of::<RootProbe>())).unwrap();
    root.wait_for("text:根内容").unwrap();
    assert_eq!(root.screen().count("text:Overview").unwrap(), 0);
    let mut detail = Headless::start(EngineConfig::new(Root::of::<DetailProbe>())).unwrap();
    detail.wait_for("text:财富").unwrap();
    detail.wait_for("text:详情内容").unwrap();
}
