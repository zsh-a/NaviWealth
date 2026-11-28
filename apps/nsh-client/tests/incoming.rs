//! Content shared from other apps, as the TSX entry forwards the Android
//! host's copies: images and text become an unsent conversation message, a statement
//! file opens its review, anything else is declined, and nothing outside the
//! share folder is read.
mod common;

use std::sync::Mutex;

use common::*;

/// The startup queue is process-wide; one share flow at a time.
static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());

/// A copy in the host's share folder under `dir`.
fn copy(dir: &Path, name: &str, bytes: &[u8]) -> PathBuf {
    let folder = dir.join("naviwealth-incoming");
    std::fs::create_dir_all(&folder).unwrap();
    let path = folder.join(name);
    std::fs::write(&path, bytes).unwrap();
    path
}

fn share(text: &str, files: Vec<(&Path, &str, &str)>) -> (tempfile::TempDir, Headless) {
    let dir = tempfile::tempdir().unwrap();
    let app = share_in(dir.path(), text, files);
    (dir, app)
}

/// Starts the app keeping its data under `dir`, with one share queued.
fn share_in(dir: &Path, text: &str, files: Vec<(&Path, &str, &str)>) -> Headless {
    let files: Vec<_> = files
        .into_iter()
        .map(|(path, name, mime)| json!({"path": path, "name": name, "mime": mime}))
        .collect();
    naviwealth_app::share_on_start(json!({"text": text, "files": files})).unwrap();
    let network = Arc::new(StubNetwork::new(Vec::<(String, StubResponse)>::new()));
    let (app, _) = start_in(Some(dir), account(true), Some(network.clone()));
    assert!(
        network.requests().is_empty(),
        "nothing is sent before the owner does"
    );
    app
}

fn eventually_gone(path: &Path) {
    for _ in 0..100 {
        if !path.exists() {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("{} was not removed", path.display());
}

#[test]
fn shared_images_and_text_open_an_unsent_conversation() -> Result<(), String> {
    let _one = ONE_AT_A_TIME.lock().unwrap_or_else(|e| e.into_inner());
    let source = tempfile::tempdir().unwrap();
    let first = copy(source.path(), "a1.png", &photo());
    let second = copy(source.path(), "a2.png", &photo());
    let (dir, mut app) = share(
        "  Lunch receipt  ",
        vec![
            (&first, "IMG_1.png", "image/png"),
            (&second, "IMG_2.png", "image/png"),
        ],
    );
    app.wait_for("label:Message")?;
    app.wait_for("label:Remove photo")?;
    assert_eq!(
        app.screen().input_text("label:Message")?,
        Some("Lunch receipt")
    );
    for hidden in [
        "Review before saving",
        "Confirm and save",
        "Editing selected record",
    ] {
        assert!(
            !app.shows(hidden),
            "unsent share has no review control: {hidden}"
        );
    }
    assert_eq!(
        app.screen().count("label:Remove photo")?,
        2,
        "both images are staged, not sent"
    );
    eventually_gone(&first);
    eventually_gone(&second);
    // Back and reopening preserve unsent text/photos in the same conversation.
    app.press("label:Back")?;
    app.press("label:Conversation")?;
    assert_eq!(
        app.screen().input_text("label:Message")?,
        Some("Lunch receipt")
    );
    assert_eq!(app.screen().count("label:Remove photo")?, 2);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let body: String = db
        .query_row("SELECT body FROM assistant_sessions", [], |row| row.get(0))
        .unwrap();
    let session: Value = serde_json::from_str(&body).unwrap();
    assert!(
        session["messages"]
            .as_array()
            .unwrap()
            .iter()
            .all(|message| message["role"] != "user"),
        "sharing does not submit a user turn"
    );
    assert!(stored_meals(dir.path()).is_empty());
    Ok(())
}

#[test]
fn a_shared_statement_opens_its_review_and_other_files_are_declined() -> Result<(), String> {
    let _one = ONE_AT_A_TIME.lock().unwrap_or_else(|e| e.into_inner());
    let source = tempfile::tempdir().unwrap();
    let csv = format!(
        "支付宝交易记录明细\n交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号\n{} 12:00:00,餐饮美食,Shared lunch,午餐,支出,31.50,余额,交易成功,id-one,order-one\n",
        today()
    );
    let statement = copy(source.path(), "s1", csv.as_bytes());
    let data = tempfile::tempdir().unwrap();
    let mut app = share_in(
        data.path(),
        "",
        vec![(&statement, "alipay.csv", "text/csv")],
    );
    app.wait_for("alipay.csv")?;
    eventually_gone(&statement);
    drop(app);

    // A review in progress is kept; the second file is declined and removed.
    let second = copy(source.path(), "s2", csv.as_bytes());
    let mut app = share_in(data.path(), "", vec![(&second, "second.csv", "text/csv")]);
    app.wait_for("text:/^Finish or discard the statement in review/")?;
    eventually_gone(&second);
    app.press("label:Records")?;
    app.press("Import statement")?;
    app.wait_for("alipay.csv")?;
    assert!(!app.shows("second.csv"));
    drop(app);

    let pdf = copy(source.path(), "p1", b"%PDF-1.7");
    let (_dir, mut app) = share("", vec![(&pdf, "bill.pdf", "application/pdf")]);
    app.wait_for("text:/^Can't open what was shared/")?;
    eventually_gone(&pdf);
    Ok(())
}

#[test]
fn nothing_outside_the_share_folder_is_read_or_removed() -> Result<(), String> {
    let _one = ONE_AT_A_TIME.lock().unwrap_or_else(|e| e.into_inner());
    let source = tempfile::tempdir().unwrap();
    let outside = source.path().join("private.png");
    std::fs::write(&outside, photo()).unwrap();
    let (_dir, mut app) = share("", vec![(&outside, "private.png", "image/png")]);
    app.wait_for("text:/^Can't open what was shared/")?;
    assert!(outside.exists());
    assert_eq!(app.screen().count("label:Remove photo")?, 0);
    Ok(())
}
