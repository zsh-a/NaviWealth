//! File picker, durable review, confirmation and repeat imports.
mod common;
use common::*;
use navi_finance::{
    account::{Account, AccountPurpose},
    import::{Rules, store},
    repository,
};
fn pick(app: &mut Headless, name: &str, text: &str) {
    let name = name.to_owned();
    let bytes = text.as_bytes().to_vec();
    app.on_pick(move |request| {
        assert!(matches!(request, nsh_core::picker::Pick::Files(_)));
        vec![PickedFile::new(
            name.clone(),
            "text/csv",
            ImageData::new(bytes.clone()),
        )]
    });
}
fn text() -> String {
    format!(
        "支付宝交易记录明细\n交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号\n{} 12:00:00,餐饮美食,Statement lunch,午餐,支出,31.50,余额,交易成功,id-one,order-one\n",
        today()
    )
}
fn enter(app: &mut Headless) -> Result<(), String> {
    app.press("label:Records")?;
    app.press("Import statement")?;
    Ok(())
}
#[test]
fn picker_review_resumes_and_confirmation_remembers_mapping_only_once() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let network = Arc::new(StubNetwork::new(Vec::<(String, StubResponse)>::new()));
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(network.clone()));
    pick(&mut app, "alipay.csv", &text());
    enter(&mut app)?;
    app.press("Choose statement file")?;
    app.wait_for("alipay.csv")?;
    app.press("text:/^余额 · /")?;
    app.press("label:Account type, Bank account")?;
    app.press("label:Digital wallet")?;
    app.type_text("label:Account name", "Import wallet")?;
    app.press("Use account")?;
    app.wait_for("Import 1")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(repository::transactions(&db).unwrap().is_empty());
    assert_eq!(repository::rules(&db).unwrap(), Rules::default());
    let wallet = Account::parse("资产:Import wallet").unwrap();
    assert!(!repository::accounts(&db).unwrap().contains(&wallet));
    assert_eq!(
        store::active(&db)
            .unwrap()
            .unwrap()
            .pending_purposes
            .get(&wallet),
        Some(&AccountPurpose::Wallet)
    );
    drop(db);
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(network.clone()));
    enter(&mut app)?;
    app.wait_for("alipay.csv")?;
    app.press("Import 1")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert_eq!(repository::transactions(&db).unwrap().len(), 1);
    assert!(store::active(&db).unwrap().is_none());
    assert_eq!(
        repository::rules(&db).unwrap().methods["alipay"]["余额"],
        wallet
    );
    assert_eq!(
        repository::account_purposes(&db).unwrap().get(&wallet),
        Some(&AccountPurpose::Wallet)
    );
    pick(&mut app, "alipay.csv", &text());
    app.press("Import statement")?;
    app.press("Choose statement file")?;
    app.wait_for("text:/Already imported/")?;
    assert!(app.shows("Import 0"));
    assert_eq!(repository::transactions(&db).unwrap().len(), 1);
    assert!(network.requests().is_empty());
    Ok(())
}
#[test]
fn pdf_and_cancelled_picker_never_make_financial_drafts() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    enter(&mut app)?;
    app.on_pick(|_| Vec::new());
    app.press("Choose statement file")?;
    app.wait_for("Choose statement file")?;
    pick(&mut app, "card.pdf", "%PDF-1.7");
    app.press("Choose statement file")?;
    app.wait_for("text:/^Cannot read this statement/")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(store::active(&db).unwrap().is_none());
    assert!(repository::transactions(&db).unwrap().is_empty());
    Ok(())
}
