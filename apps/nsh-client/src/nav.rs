//! Navigation state: the home's chosen tab, and the pages open over the
//! home, bottom to top. Putting a route in pushes its page; taking it out
//! pops it.

use nsh_core::prelude::*;

use crate::domain::meal::Day;

/// A page over Today.
#[derive(Debug, Clone, PartialEq)]
pub enum Route {
    /// A new meal on `day`, from the picked photo `capture` or by hand.
    NewMeal {
        day: Day,
        capture: Option<u64>,
    },
    /// The saved meal with this id.
    EditMeal(String),
    /// The recognition draft with this id.
    Pending(String),
    /// Snapshot of the records committed together, in their reviewed order.
    SavedBatch {
        id: String,
        records: std::rc::Rc<[crate::domain::capture::Record]>,
    },
    SavedObservation {
        id: String,
        record: std::rc::Rc<crate::domain::capture::Record>,
    },
    SavedTrade {
        security: String,
        trade: String,
    },
    /// Settings.
    Settings,
    /// Height, age and sex used for health calculations.
    BodyProfile,
    /// The vision model account, from Settings.
    ModelSettings,
    /// Backup and restore, from Settings.
    BackupSettings,
    /// An own financial account.
    Account(String),
    AccountCheck(String),
    Holding(String),
    AssetHistory {
        comparison: Option<(Day, Day)>,
    },
    ClosedHoldings,
    StatementImport,
    PricesAndRates(Option<String>),
    ExchangeRate(navi_finance::currency::Currency),
    HistoricalRate {
        currency: navi_finance::currency::Currency,
        from: Day,
        to: Day,
    },
    Spending {
        from: Day,
        to: Day,
        category: Option<String>,
        currency: navi_finance::currency::Currency,
    },
}

/// The home's tabs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Tab {
    #[default]
    Today,
    Records,
    Assets,
    Review,
}

impl Tab {
    pub const ALL: [Tab; 4] = [Tab::Today, Tab::Records, Tab::Assets, Tab::Review];
}

#[derive(Clone, Copy, Default, PartialEq)]
struct Chosen(Tab);

/// The chosen tab (tracked).
pub fn tab() -> Tab {
    global::<Chosen>().get().0
}

/// Shows `tab`.
pub fn select(tab: Tab) {
    global::<Chosen>().set(Chosen(tab));
}

impl Route {
    /// Its identity in the stack.
    pub fn key(&self) -> String {
        match self {
            Self::SavedBatch { id, .. } => format!("saved-batch:{id}"),
            Self::SavedObservation { id, .. } => format!("saved-observation:{id}"),
            _ => format!("{self:?}"),
        }
    }
}

#[derive(Clone, Default, PartialEq)]
struct Routes(Vec<Route>);

fn routes() -> Signal<Routes> {
    global::<Routes>()
}

/// The open routes (tracked).
pub fn open() -> Vec<Route> {
    routes().with(|routes| routes.0.clone())
}

/// Opens `route`; a second press while it is open opens nothing more.
pub fn push(route: Route) {
    routes().update(|routes| {
        if !routes.0.contains(&route) {
            routes.0.push(route);
        }
    });
}

/// Closes the top page.
pub fn pop() {
    routes().update(|routes| {
        routes.0.pop();
    });
}

/// Keeps `depth` pages: the user went back natively.
pub fn truncate(depth: usize) {
    routes().update(|routes| routes.0.truncate(depth));
}
