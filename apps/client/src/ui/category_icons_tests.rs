use super::*;
#[test]
fn every_builtin_category_has_its_intended_icon_without_implicit_fallback() {
    use CategoryIcon::*;
    let expected = [
        Food,
        Basket,
        Coffee,
        Train,
        Car,
        Home,
        Bolt,
        Chair,
        Bag,
        Subscription,
        Film,
        Health,
        Fitness,
        Book,
        Plane,
        Phone,
        Gift,
        Family,
        Pet,
        Chart,
        Receipt,
        Tax,
        Interest,
        Tax,
        Tax,
        Tag,
    ];
    let presets = naviwealth_finance::system_accounts::EXPENSE_CATEGORY_PRESETS;
    assert_eq!(
        presets.len(),
        expected.len(),
        "new builtins need an explicit icon expectation"
    );
    for (preset, expected) in presets.iter().zip(expected) {
        assert_eq!(
            category_name(preset.name_zh),
            Some(expected),
            "{}",
            preset.key
        );
        assert_eq!(
            category_name(preset.name_en),
            Some(expected),
            "{}",
            preset.key
        );
        assert!(expected.markup().contains("<svg"));
    }
    for (name, expected) in [
        ("工资薪酬", Briefcase),
        ("股息红利", Coins),
        ("利息收入", Interest),
        ("资本利得", Chart),
        ("期权收入", Chart),
        ("其他收入", Wallet),
    ] {
        assert_eq!(category_name(name), Some(expected));
    }
    assert_eq!(category_name("自定义分类"), None);
    assert_eq!(category_name("其他支出"), Some(Tag));
    assert_ne!(Coffee.markup(), Food.markup());
}
#[test]
fn demo_coffee_is_categorized_as_coffee_and_budget_totals_stay_consistent() {
    let data: serde_json::Value =
        serde_json::from_str(include_str!("../../examples/fixtures/direction_a.json")).unwrap();
    let entries = data["entries"].as_array().unwrap();
    let coffee = entries
        .iter()
        .filter(|e| {
            e["name"]
                .as_str()
                .is_some_and(|n| n.contains("咖啡") || n == "星巴克")
        })
        .collect::<Vec<_>>();
    assert_eq!(coffee.len(), 5);
    for entry in coffee {
        assert_eq!(entry["category"], "coffee");
    }
    let categories = data["categories"].as_array().unwrap();
    for category in categories {
        let spent: i64 = entries
            .iter()
            .filter(|e| e["kind"] == "expense" && e["category"] == category["id"])
            .map(|e| e["cents"].as_i64().unwrap())
            .sum();
        assert_eq!(spent, category["spent"].as_i64().unwrap());
        assert!(category_name(category["full"].as_str().unwrap()).is_some());
    }
    let expense: i64 = entries
        .iter()
        .filter(|e| e["kind"] == "expense")
        .map(|e| e["cents"].as_i64().unwrap())
        .sum();
    let limit: i64 = categories
        .iter()
        .map(|c| c["limit"].as_i64().unwrap())
        .sum();
    assert_eq!((expense, limit, limit - expense), (873640, 1200000, 326360));
}
