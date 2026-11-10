//! The seeded system account tree (income / expense / equity) and the
//! user-facing expense categories derived from it. Ported from the
//! Flutter SSOT (`account_repository_system_account_seeds.dart` +
//! `expense_category_presets.dart`).

use lifeos::sync::{MutationStamper, SyncMeta};
use rusqlite::{Connection, params};

use crate::error::Result;
use crate::models::AccountSide;
use crate::tables::{ACCOUNTS_TABLE, CATEGORIES_TABLE};

/// One seeded system account. Expense rows derive from
/// [`EXPENSE_CATEGORY_PRESETS`].
struct SystemAccountSeed {
    /// Path under the user's prefix, e.g. `income`, `expense:dining`.
    path: String,
    parent_path: Option<String>,
    /// English Beancount-canonical name.
    name: &'static str,
    category: AccountSide,
    icon: &'static str,
    color: &'static str,
}

pub struct ExpenseCategoryPreset {
    pub key: &'static str,
    pub parent_key: Option<&'static str>,
    pub name_en: &'static str,
    pub name_zh: &'static str,
    pub icon: &'static str,
    pub color: &'static str,
}

impl ExpenseCategoryPreset {
    /// Path under the `expense:` tree (`expense:trading:fee`).
    pub fn account_path(&self) -> String {
        format!("expense:{}", self.key)
    }

    pub fn parent_account_path(&self) -> String {
        match self.parent_key {
            Some(parent) => format!("expense:{parent}"),
            None => "expense".to_owned(),
        }
    }
}

/// Built-in category tree: the only seed-shape SSOT. Ledger accounts are
/// hidden posting targets derived from this taxonomy.
pub const EXPENSE_CATEGORY_PRESETS: &[ExpenseCategoryPreset] = &[
    ExpenseCategoryPreset {
        key: "dining",
        parent_key: None,
        name_en: "Dining",
        name_zh: "餐饮",
        icon: "restaurant",
        color: "#EA580C",
    },
    ExpenseCategoryPreset {
        key: "groceries",
        parent_key: None,
        name_en: "Groceries",
        name_zh: "生鲜日用",
        icon: "local_grocery_store",
        color: "#65A30D",
    },
    ExpenseCategoryPreset {
        key: "coffee",
        parent_key: None,
        name_en: "Coffee",
        name_zh: "咖啡",
        icon: "local_cafe",
        color: "#CA8A04",
    },
    ExpenseCategoryPreset {
        key: "transport",
        parent_key: None,
        name_en: "Transport",
        name_zh: "公共交通",
        icon: "directions_bus",
        color: "#0284C7",
    },
    ExpenseCategoryPreset {
        key: "rideHailing",
        parent_key: None,
        name_en: "Ride Hailing",
        name_zh: "打车",
        icon: "local_taxi",
        color: "#0F766E",
    },
    ExpenseCategoryPreset {
        key: "housing",
        parent_key: None,
        name_en: "Housing",
        name_zh: "住房",
        icon: "home",
        color: "#4F46E5",
    },
    ExpenseCategoryPreset {
        key: "utilities",
        parent_key: None,
        name_en: "Utilities",
        name_zh: "水电燃气",
        icon: "bolt",
        color: "#EAB308",
    },
    ExpenseCategoryPreset {
        key: "household",
        parent_key: None,
        name_en: "Household",
        name_zh: "家居日用",
        icon: "chair",
        color: "#0891B2",
    },
    ExpenseCategoryPreset {
        key: "shopping",
        parent_key: None,
        name_en: "Shopping",
        name_zh: "购物",
        icon: "shopping_bag",
        color: "#DB2777",
    },
    ExpenseCategoryPreset {
        key: "subscriptions",
        parent_key: None,
        name_en: "Subscriptions",
        name_zh: "订阅",
        icon: "credit_card",
        color: "#7C3AED",
    },
    ExpenseCategoryPreset {
        key: "entertainment",
        parent_key: None,
        name_en: "Entertainment",
        name_zh: "娱乐",
        icon: "sports_esports",
        color: "#C026D3",
    },
    ExpenseCategoryPreset {
        key: "medical",
        parent_key: None,
        name_en: "Medical",
        name_zh: "医疗",
        icon: "medical_services",
        color: "#E11D48",
    },
    ExpenseCategoryPreset {
        key: "fitness",
        parent_key: None,
        name_en: "Fitness",
        name_zh: "运动健身",
        icon: "fitness_center",
        color: "#059669",
    },
    ExpenseCategoryPreset {
        key: "education",
        parent_key: None,
        name_en: "Education",
        name_zh: "教育",
        icon: "school",
        color: "#2563EB",
    },
    ExpenseCategoryPreset {
        key: "travel",
        parent_key: None,
        name_en: "Travel",
        name_zh: "旅行",
        icon: "flight",
        color: "#1D4ED8",
    },
    ExpenseCategoryPreset {
        key: "communication",
        parent_key: None,
        name_en: "Communication",
        name_zh: "通讯",
        icon: "smartphone",
        color: "#0E7490",
    },
    ExpenseCategoryPreset {
        key: "gift",
        parent_key: None,
        name_en: "Gift",
        name_zh: "礼物",
        icon: "card_giftcard",
        color: "#D97706",
    },
    ExpenseCategoryPreset {
        key: "familySupport",
        parent_key: None,
        name_en: "Family Support",
        name_zh: "家庭支持",
        icon: "redeem",
        color: "#BE123C",
    },
    ExpenseCategoryPreset {
        key: "pets",
        parent_key: None,
        name_en: "Pets",
        name_zh: "宠物",
        icon: "pets",
        color: "#9333EA",
    },
    ExpenseCategoryPreset {
        key: "trading",
        parent_key: None,
        name_en: "Trading",
        name_zh: "交易",
        icon: "show_chart",
        color: "#334155",
    },
    ExpenseCategoryPreset {
        key: "trading:fee",
        parent_key: Some("trading"),
        name_en: "Trading Fee",
        name_zh: "手续费",
        icon: "receipt_long",
        color: "#64748B",
    },
    ExpenseCategoryPreset {
        key: "trading:tax",
        parent_key: Some("trading"),
        name_en: "Trading Tax",
        name_zh: "交易税费",
        icon: "request_quote",
        color: "#9F1239",
    },
    ExpenseCategoryPreset {
        key: "trading:interest",
        parent_key: Some("trading"),
        name_en: "Trading Interest",
        name_zh: "融资利息",
        icon: "credit_card",
        color: "#475569",
    },
    ExpenseCategoryPreset {
        key: "tax",
        parent_key: None,
        name_en: "Tax",
        name_zh: "税务",
        icon: "request_quote",
        color: "#B91C1C",
    },
    ExpenseCategoryPreset {
        key: "tax:withholding",
        parent_key: Some("tax"),
        name_en: "Withholding Tax",
        name_zh: "预扣税",
        icon: "request_quote",
        color: "#881337",
    },
    ExpenseCategoryPreset {
        key: "other",
        parent_key: None,
        name_en: "Other Expense",
        name_zh: "其他支出",
        icon: "more_horiz",
        color: "#747C8C",
    },
];

/// Roots, income leaves and equity leaves. Expense leaves are appended
/// from [`EXPENSE_CATEGORY_PRESETS`] at seed time. Iterated in
/// parent-before-child order.
fn system_account_seeds() -> Vec<SystemAccountSeed> {
    fn seed(
        path: &str,
        parent: Option<&str>,
        name: &'static str,
        category: AccountSide,
        icon: &'static str,
        color: &'static str,
    ) -> SystemAccountSeed {
        SystemAccountSeed {
            path: path.to_owned(),
            parent_path: parent.map(str::to_owned),
            name,
            category,
            icon,
            color,
        }
    }

    let mut seeds = vec![
        seed(
            "income",
            None,
            "Income",
            AccountSide::Income,
            "south_west",
            "#10B981",
        ),
        seed(
            "expense",
            None,
            "Expenses",
            AccountSide::Expense,
            "north_east",
            "#EF4444",
        ),
        seed(
            "equity",
            None,
            "Equity",
            AccountSide::Equity,
            "account_balance",
            "#3B82F6",
        ),
        seed(
            "income:salary",
            Some("income"),
            "Salary",
            AccountSide::Income,
            "work",
            "#10B981",
        ),
        seed(
            "income:dividend",
            Some("income"),
            "Dividend",
            AccountSide::Income,
            "paid",
            "#10B981",
        ),
        seed(
            "income:interest",
            Some("income"),
            "Interest",
            AccountSide::Income,
            "savings",
            "#10B981",
        ),
        seed(
            "income:capitalGains",
            Some("income"),
            "Capital Gains",
            AccountSide::Income,
            "trending_up",
            "#10B981",
        ),
        seed(
            "income:options",
            Some("income"),
            "Options Income",
            AccountSide::Income,
            "show_chart",
            "#10B981",
        ),
        seed(
            "income:other",
            Some("income"),
            "Other Income",
            AccountSide::Income,
            "more_horiz",
            "#10B981",
        ),
    ];
    for preset in EXPENSE_CATEGORY_PRESETS {
        seeds.push(SystemAccountSeed {
            path: preset.account_path(),
            parent_path: Some(preset.parent_account_path()),
            name: preset.name_en,
            category: AccountSide::Expense,
            icon: preset.icon,
            color: preset.color,
        });
    }
    seeds.extend([
        seed(
            "equity:openingBalance",
            Some("equity"),
            "Opening Balance",
            AccountSide::Equity,
            "flag",
            "#3B82F6",
        ),
        seed(
            "equity:splits",
            Some("equity"),
            "Stock Splits",
            AccountSide::Equity,
            "call_split",
            "#3B82F6",
        ),
        seed(
            "equity:adjustments",
            Some("equity"),
            "Adjustments",
            AccountSide::Equity,
            "tune",
            "#3B82F6",
        ),
    ]);
    seeds
}

/// Stable id of a seeded system account for `owner`.
pub fn system_account_id(owner: &str, path: &str) -> String {
    format!("system-account:{owner}:{path}")
}

/// Seed the system account tree (parent before child) and the user-facing
/// expense categories. Idempotent. System ledger accounts carry an empty
/// `type` (they are not custody accounts); `category` carries the side.
pub fn seed_system_accounts(conn: &Connection, stamper: &MutationStamper) -> Result<()> {
    let owner = stamper.owner_user_id.clone();
    let stamp = stamper.stamp(conn)?;
    let sync = SyncMeta::from_stamp(&stamp);

    for seed in system_account_seeds() {
        let id = system_account_id(&owner, &seed.path);
        let parent_id = seed.parent_path.map(|p| system_account_id(&owner, &p));
        conn.execute(
            &format!(
                r#"INSERT OR IGNORE INTO "{ACCOUNTS_TABLE}" (id, type, name, currency, institution, account_number, note, archived, category, parent_id, icon, color, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
                 VALUES (?1, ?2, ?3, ?4, NULL, NULL, NULL, 0, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, NULL)"#
            ),
            params![
                id,
                "",
                seed.name,
                "",
                seed.category.as_str(),
                parent_id,
                seed.icon,
                seed.color,
                sync.owner_user_id,
                sync.updated_at,
                sync.updated_by_device,
                sync.hlc,
            ],
        )?;
    }

    // User-facing expense categories pointing at their hidden ledger
    // accounts. `name` is the Beancount-canonical English name;
    // `name_override` carries the Chinese display name.
    for (index, preset) in EXPENSE_CATEGORY_PRESETS.iter().enumerate() {
        let id = format!("system-category:{owner}:{}", preset.key);
        let ledger_account_id = system_account_id(&owner, &preset.account_path());
        conn.execute(
            &format!(
                r#"INSERT OR IGNORE INTO "{CATEGORIES_TABLE}" (id, name, name_override, system_key, parent_id, ledger_account_id, icon, color, sort_order, archived, merged_into_id, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0, NULL, ?10, ?11, ?12, ?13, NULL)"#
            ),
            params![
                id,
                preset.name_en,
                preset.name_zh,
                preset.key,
                preset.parent_key.map(|p| format!("system-category:{owner}:{p}")),
                ledger_account_id,
                preset.icon,
                preset.color,
                index as i64,
                sync.owner_user_id,
                sync.updated_at,
                sync.updated_by_device,
                sync.hlc,
            ],
        )?;
    }
    Ok(())
}

/// A display name for a category in the active language.
pub fn category_display_name<'a>(
    name: &'a str,
    name_override: Option<&'a str>,
    zh: bool,
) -> &'a str {
    if zh {
        name_override.unwrap_or(name)
    } else {
        name
    }
}
