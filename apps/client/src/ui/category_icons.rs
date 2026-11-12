//! A missing category mapping is distinct from an intentional generic tag.
use super::*;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CategoryIcon {
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
    Wallet,
    Briefcase,
    Coins,
    Swap,
    Flag,
    Tag,
}
impl CategoryIcon {
    fn markup(self) -> &'static str {
        match self {
            Self::Food => include_str!("../../assets/icons/categories/food.svg"),
            Self::Basket => include_str!("../../assets/icons/categories/basket.svg"),
            Self::Coffee => include_str!("../../assets/icons/categories/coffee.svg"),
            Self::Train => include_str!("../../assets/icons/categories/train.svg"),
            Self::Car => include_str!("../../assets/icons/categories/car.svg"),
            Self::Home => include_str!("../../assets/icons/categories/home.svg"),
            Self::Bolt => include_str!("../../assets/icons/categories/bolt.svg"),
            Self::Chair => include_str!("../../assets/icons/categories/chair.svg"),
            Self::Bag => include_str!("../../assets/icons/categories/bag.svg"),
            Self::Subscription => include_str!("../../assets/icons/categories/subscription.svg"),
            Self::Film => include_str!("../../assets/icons/categories/film.svg"),
            Self::Health => include_str!("../../assets/icons/categories/health.svg"),
            Self::Fitness => include_str!("../../assets/icons/categories/fitness.svg"),
            Self::Book => include_str!("../../assets/icons/categories/book.svg"),
            Self::Plane => include_str!("../../assets/icons/categories/plane.svg"),
            Self::Phone => include_str!("../../assets/icons/categories/phone.svg"),
            Self::Gift => include_str!("../../assets/icons/categories/gift.svg"),
            Self::Family => include_str!("../../assets/icons/categories/family.svg"),
            Self::Pet => include_str!("../../assets/icons/categories/pet.svg"),
            Self::Chart => include_str!("../../assets/icons/categories/chart.svg"),
            Self::Receipt => include_str!("../../assets/icons/categories/receipt.svg"),
            Self::Tax => include_str!("../../assets/icons/categories/tax.svg"),
            Self::Interest => include_str!("../../assets/icons/categories/interest.svg"),
            Self::Wallet => include_str!("../../assets/icons/categories/wallet.svg"),
            Self::Briefcase => include_str!("../../assets/icons/categories/briefcase.svg"),
            Self::Coins => include_str!("../../assets/icons/categories/coins.svg"),
            Self::Swap => include_str!("../../assets/icons/categories/swap.svg"),
            Self::Flag => include_str!("../../assets/icons/categories/flag.svg"),
            Self::Tag => include_str!("../../assets/icons/categories/tag.svg"),
        }
    }
}
fn category_name(name: &str) -> Option<CategoryIcon> {
    Some(match name {
        "餐饮" | "Dining" => CategoryIcon::Food,
        "生鲜日用" | "Groceries" => CategoryIcon::Basket,
        "咖啡" | "Coffee" => CategoryIcon::Coffee,
        "公共交通" | "Transport" => CategoryIcon::Train,
        "打车" | "Ride Hailing" => CategoryIcon::Car,
        "住房" | "Housing" => CategoryIcon::Home,
        "水电燃气" | "Utilities" => CategoryIcon::Bolt,
        "家居日用" | "Household" => CategoryIcon::Chair,
        "购物" | "Shopping" => CategoryIcon::Bag,
        "订阅" | "Subscriptions" => CategoryIcon::Subscription,
        "娱乐" | "Entertainment" => CategoryIcon::Film,
        "医疗" | "Medical" => CategoryIcon::Health,
        "运动健身" | "Fitness" => CategoryIcon::Fitness,
        "教育" | "Education" => CategoryIcon::Book,
        "旅行" | "Travel" => CategoryIcon::Plane,
        "通讯" | "Communication" => CategoryIcon::Phone,
        "礼物" | "Gift" => CategoryIcon::Gift,
        "家庭支持" | "Family Support" => CategoryIcon::Family,
        "宠物" | "Pets" => CategoryIcon::Pet,
        "交易" | "Trading" => CategoryIcon::Chart,
        "手续费" | "Trading Fee" => CategoryIcon::Receipt,
        "交易税费" | "Trading Tax" => CategoryIcon::Tax,
        "融资利息" | "Trading Interest" => CategoryIcon::Interest,
        "税务" | "Tax" => CategoryIcon::Tax,
        "预扣税" | "Withholding Tax" => CategoryIcon::Tax,
        "其他支出" | "Other Expense" => CategoryIcon::Tag,
        "工资薪酬" | "Salary" => CategoryIcon::Briefcase,
        "股息红利" | "Dividend" => CategoryIcon::Coins,
        "利息收入" | "Interest" => CategoryIcon::Interest,
        "资本利得" | "Capital Gains" => CategoryIcon::Chart,
        "期权收入" | "Options Income" => CategoryIcon::Chart,
        "其他收入" | "Other Income" => CategoryIcon::Wallet,
        "收入" => CategoryIcon::Wallet,
        "支出" => CategoryIcon::Tag,
        "转账" => CategoryIcon::Swap,
        "期初余额" => CategoryIcon::Flag,
        "投资" => CategoryIcon::Chart,
        _ => return None,
    })
}
pub fn category_icon(name: &str) -> impl Element {
    let icon = category_name(name).unwrap_or(CategoryIcon::Tag);
    svg(nsh_core::element::ImageSrc::svg_markup(icon.markup()))
        .w(move || px(token("icon-size")))
        .h(move || px(token("icon-size")))
        .flex_shrink_0()
        .text_color(move || theme().muted_foreground)
}
#[cfg(test)]
#[path = "category_icons_tests.rs"]
mod tests;
