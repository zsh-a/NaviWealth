//! Measurement dates stay in the accessible label and share the trend caption.
mod common;
use common::*;

#[test]
fn today_omits_its_date_and_older_readings_share_the_trend_caption() -> Result<(), String> {
    use nsh_core::platform::{Locale, LocaleSettings};
    for back in [0, 1] {
        let dir = tempfile::tempdir().unwrap();
        let (app, _) = start_in(Some(dir.path()), Vec::new(), None);
        drop(app);
        let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
        let day = today().plus_days(-back);
        for offset in 0..15 {
            db.execute(
                "INSERT INTO weights(day,kg,logged_at_ms) VALUES(?1,?2,0)",
                rusqlite::params![
                    day.plus_days(-offset).to_string(),
                    70.0 + f64::from(offset) * 0.1
                ],
            )
            .unwrap();
        }
        drop(db);
        let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
        for (tag, title, today_label, trend) in [
            ("en", "Body metrics", "Today", "−0.7 kg · 7d"),
            ("zh-CN", "身体指标", "今天", "−0.7 kg · 7天"),
        ] {
            let locale = Locale::parse(tag).unwrap();
            app.set_environment("language", |e| {
                e.locale = locale;
                e.locale_settings = LocaleSettings::of(locale);
            })?;
            let date = if back == 0 {
                today_label.to_owned()
            } else if tag == "zh-CN" {
                format!(
                    "{}月{}日 周{}",
                    day.0.month(),
                    day.0.day(),
                    ["一", "二", "三", "四", "五", "六", "日"]
                        [day.0.weekday().to_monday_zero_offset() as usize]
                )
            } else {
                day.0.strftime("%a, %b %-d").to_string()
            };
            app.wait_for(&format!("label:{title}, 70.0 kg, {date}"))?;
            app.wait_for(&format!(
                "text:{}",
                if back == 0 {
                    trend.to_owned()
                } else {
                    format!("{date} · {trend}")
                }
            ))?;
            // The measurement date is never a standalone visual line.
            let nodes = app.screen().layout_nodes();
            let root = nodes
                .iter()
                .find(|n| n.test_id.as_deref() == Some("body-primary"))
                .unwrap();
            for node in nodes
                .iter()
                .filter(|n| n.text.as_ref().is_some_and(|t| t.text.text == date))
            {
                let mut parent = node.parent;
                while let Some(ancestor) = nodes.iter().find(|n| n.id == parent) {
                    assert_ne!(ancestor.id, root.id);
                    if ancestor.parent == parent {
                        break;
                    }
                    parent = ancestor.parent;
                }
            }
        }
    }
    Ok(())
}
