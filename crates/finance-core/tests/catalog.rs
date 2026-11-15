use finance_core::{
    catalog::{self, Manifest, SecurityBinding},
    holdings::{self, Security},
    repository,
};
use lifeos_core::sqlite::Connection;
use sha2::{Digest, Sha256};
use std::io::Write;
const BUNDLE: &str = include_str!("../../../apps/mobile/assets/catalog/securities.v1.ndjson");
fn db() -> Connection {
    let c = Connection::open_in_memory().unwrap();
    c.execute_batch("PRAGMA foreign_keys=ON").unwrap();
    c.execute_batch(repository::SCHEMA).unwrap();
    c.execute_batch(holdings::store::SCHEMA).unwrap();
    c.execute_batch(catalog::SCHEMA).unwrap();
    c
}
#[test]
fn bundled_catalog_has_verified_count_identity_and_offline_aliases() {
    let c = catalog::parse(BUNDLE).unwrap();
    assert_eq!(c.entries.len(), 23783);
    for q in ["000001", "平安银行", "pinganyinhang", "payh"] {
        assert!(
            c.search(q, 50)
                .iter()
                .any(|e| e.market == "cn_a" && e.symbol == "000001"),
            "{q}"
        )
    }
    assert!(c.search("", 50).is_empty());
    assert!(c.search(&"a".repeat(129), 50).is_empty());
    assert!(c.search("a", 1000).len() <= 50);
    assert!(
        c.search("zero-gravity", 50)
            .iter()
            .any(|e| e.symbol == "0G-USD")
    );
    assert!(
        c.search("0700", 50)
            .iter()
            .any(|e| e.market == "hk_stock" && e.supported())
    );
    let apple = c.search("aapl", 50);
    assert!(apple.iter().any(|e| e.symbol == "AAPL" && e.supported()));
}
#[test]
fn header_alone_matches_the_full_parse_and_rejects_bad_headers() {
    let full = catalog::parse(BUNDLE).unwrap();
    let header = catalog::header(BUNDLE).unwrap();
    assert_eq!(header.version, full.header.version);
    assert_eq!(header.count, full.header.count);
    assert!(catalog::header("").is_err());
    assert!(catalog::header("{\"version\":\"bad\",\"checksum\":\"0\",\"count\":1}").is_err());
}
#[test]
fn update_verification_and_atomic_install_retain_old_catalog() {
    let c = db();
    let old = catalog::install(&c, BUNDLE).unwrap();
    let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    gz.write_all(BUNDLE.as_bytes()).unwrap();
    let gz = gz.finish().unwrap();
    let json = serde_json::json!({"schema":1,"version":old.header.version,"checksum":old.header.checksum,"count":old.header.count,"sha256":format!("{:x}",Sha256::digest(BUNDLE)),"asset":"securities.ndjson.gz","gzip_sha256":format!("{:x}",Sha256::digest(&gz)),"gzip_size":gz.len()});
    let m = Manifest::parse(&json.to_string()).unwrap();
    assert_eq!(m.verify(&gz).unwrap(), BUNDLE);
    let mut corrupt = gz.clone();
    corrupt[20] ^= 1;
    assert!(m.verify(&corrupt).is_err());
    assert!(catalog::install(&c, &BUNDLE.replacen("平安银行", "坏数据", 1)).is_err());
    assert_eq!(
        catalog::current(&c).unwrap().unwrap().header.checksum,
        old.header.checksum
    );
    for (key, value) in [
        ("sha256", serde_json::Value::String("0".repeat(64))),
        ("count", serde_json::Value::from(old.header.count + 1)),
        ("checksum", serde_json::Value::String("0".repeat(16))),
        ("gzip_size", serde_json::Value::from(gz.len() + 1)),
    ] {
        let mut wrong = json.clone();
        wrong[key] = value;
        assert!(
            Manifest::parse(&wrong.to_string())
                .unwrap()
                .verify(&gz)
                .is_err(),
            "{key}"
        );
        assert_eq!(
            catalog::current(&c).unwrap().unwrap().header.checksum,
            old.header.checksum
        );
    }
    let mut bad = json.clone();
    bad["asset"] = "../bad.gz".into();
    assert!(Manifest::parse(&bad.to_string()).is_err());
    bad = json;
    bad["schema"] = 2.into();
    assert!(Manifest::parse(&bad.to_string()).is_err());
}
#[test]
fn explicit_binding_preserves_security_and_rejects_foreign_currency() {
    let c = db();
    let sec = Security::new("manual-1", "My bank shares").unwrap();
    c.execute(
        "INSERT INTO finance_accounts(name) VALUES(?1)",
        [sec.account.as_str()],
    )
    .unwrap();
    c.execute(
        "INSERT INTO finance_securities VALUES(?1,?2,?3,?4)",
        lifeos_core::sqlite::params![
            sec.id,
            sec.name,
            sec.name.to_lowercase(),
            sec.account.as_str()
        ],
    )
    .unwrap();
    assert!(catalog::bindings(&c).unwrap().is_empty());
    let b = SecurityBinding {
        security: sec.id.clone(),
        market: "cn_a".into(),
        symbol: "000001".into(),
        currency: "CNY".into(),
    };
    catalog::bind(&c, &b).unwrap();
    assert_eq!(holdings::store::load(&c).unwrap().securities, vec![sec]);
    assert_eq!(catalog::bindings(&c).unwrap(), vec![b.clone()]);
    for (market, symbol, currency) in [
        ("us_stock", "AAPL", "USD"),
        ("hk_stock", "00001", "HKD"),
        ("cn_a", "600000", "USD"),
        ("cn_a", "bad", "CNY"),
    ] {
        assert!(
            catalog::bind(
                &c,
                &SecurityBinding {
                    security: b.security.clone(),
                    market: market.into(),
                    symbol: symbol.into(),
                    currency: currency.into()
                }
            )
            .is_err()
        );
    }
    assert_eq!(catalog::bindings(&c).unwrap(), vec![b]);
}

#[test]
fn relink_removes_provider_marks_atomically_but_keeps_manual_prices() {
    let c = db();
    c.execute_batch(finance_core::market::SCHEMA).unwrap();
    let sec = Security::new("s-1", "Bank").unwrap();
    c.execute(
        "INSERT INTO finance_accounts VALUES(?1)",
        [sec.account.as_str()],
    )
    .unwrap();
    c.execute(
        "INSERT INTO finance_securities VALUES(?1,?2,?3,?4)",
        lifeos_core::sqlite::params![sec.id, sec.name, "bank", sec.account.as_str()],
    )
    .unwrap();
    let mut b = SecurityBinding {
        security: sec.id.clone(),
        market: "cn_a".into(),
        symbol: "000001".into(),
        currency: "CNY".into(),
    };
    catalog::bind(&c, &b).unwrap();
    c.execute(
        "INSERT INTO finance_quotes VALUES(?1,'2026-01-01',1000000)",
        [&sec.id],
    )
    .unwrap();
    c.execute("INSERT INTO finance_market_quotes VALUES(?1,'000001.SZ','CNY','tencent',2000000,'2026-01-02T07:00:00Z','2026-01-02T07:01:00Z',0,'2026-01-02')",[&sec.id]).unwrap();
    catalog::bind(&c, &b).unwrap();
    assert_eq!(finance_core::market::load(&c).unwrap().len(), 1);
    c.execute_batch("CREATE TRIGGER fail_binding BEFORE UPDATE ON finance_security_bindings BEGIN SELECT RAISE(ABORT,'storage full'); END;").unwrap();
    b.symbol = "600000".into();
    assert!(catalog::bind(&c, &b).is_err());
    assert_eq!(finance_core::market::load(&c).unwrap().len(), 1);
    c.execute_batch("DROP TRIGGER fail_binding").unwrap();
    catalog::bind(&c, &b).unwrap();
    assert!(finance_core::market::load(&c).unwrap().is_empty());
    assert_eq!(holdings::store::load(&c).unwrap().quotes.len(), 1);
    catalog::validate(&c).unwrap();
}

#[test]
fn market_currency_and_numeric_identities_are_unambiguous() {
    for (market, symbol, currency, canonical) in [
        ("cn_a", "000001", "CNY", "000001.SZ"),
        ("hk_stock", "00001", "HKD", "00001.HK"),
        ("us_stock", "AAPL", "USD", "AAPL.US"),
    ] {
        let b = SecurityBinding {
            security: "stable-id".into(),
            market: market.into(),
            symbol: symbol.into(),
            currency: currency.into(),
        };
        assert_eq!(
            finance_core::market::canonical_binding(&b).as_deref(),
            Some(canonical)
        );
        let mut wrong = b;
        wrong.currency = if currency == "CNY" { "HKD" } else { "CNY" }.into();
        assert!(wrong.validate().is_err());
    }
}

#[test]
fn indexed_search_preserves_ranking_unicode_aliases_and_page_boundaries() {
    let c = catalog::parse(BUNDLE).unwrap();
    for query in [
        "a",
        "60",
        "000001",
        "aApL",
        "  pinganyinhang  ",
        "payh",
        "zero-gravity",
        "平安",
        "É",
        "İ",
        "00700",
        "zzzzzz",
        "\0",
    ] {
        let q = query.trim().to_lowercase();
        let mut expected = c
            .entries
            .iter()
            .filter(|e| {
                [
                    &e.symbol,
                    &e.chinese,
                    &e.english,
                    &e.pinyin,
                    &e.initials,
                    &e.aliases,
                ]
                .iter()
                .any(|field| field.to_lowercase().contains(&q))
            })
            .collect::<Vec<_>>();
        expected.sort_by_key(|e| {
            (
                e.symbol.to_lowercase() != q,
                !e.symbol.to_lowercase().starts_with(&q),
                &e.market,
                &e.symbol,
            )
        });
        assert_eq!(
            c.search(query, 40),
            expected
                .iter()
                .take(40)
                .map(|e| (*e).clone())
                .collect::<Vec<_>>(),
            "{query}"
        );
        // Page past the legacy 50-row cap without hiding unsupported listings.
        for offset in [0, 16, 48, 80] {
            assert_eq!(
                c.search_page(query, offset, 16),
                expected
                    .iter()
                    .skip(offset)
                    .take(16)
                    .map(|e| (*e).clone())
                    .collect::<Vec<_>>(),
                "{query} at {offset}"
            );
        }
    }
    assert!(c.search_page("a", 0, 0).is_empty());
    assert!(c.search_page("a", usize::MAX, 16).is_empty());
}

#[test]
fn verified_prepared_install_is_atomic_on_write_failure() {
    let c = db();
    let before = catalog::install(&c, BUNDLE).unwrap();
    let prepared = catalog::prepare(BUNDLE.to_owned()).unwrap();
    c.execute_batch("CREATE TRIGGER fail_catalog BEFORE UPDATE ON securities_catalog BEGIN SELECT RAISE(ABORT,'storage full'); END;").unwrap();
    assert!(catalog::install_prepared(&c, prepared).is_err());
    assert_eq!(
        catalog::current(&c).unwrap().unwrap().header.checksum,
        before.header.checksum
    );
}
