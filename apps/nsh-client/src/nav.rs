//! Navigation state: the home's chosen tab, and the pages open over the
//! home, bottom to top. Putting a route in pushes its page; taking it out
//! pops it.

use nsh_core::prelude::*;

use crate::domain::meal::Day;

/// A page over Today.
#[derive(Debug, Clone, PartialEq)]
pub enum Route {
    /// A new meal on `day`, from the picked photo `capture` or by hand.
    NewMeal { day: Day, capture: Option<u64> },
    /// The saved meal with this id.
    EditMeal(String),
    /// The recognition draft with this id.
    Pending(String),
    /// Settings.
    Settings,
    /// The vision model account, from Settings.
    ModelSettings,
}

/// The home's tabs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Tab {
    #[default]
    Today,
    Records,
    Review,
}

impl Tab {
    pub const ALL: [Tab; 3] = [Tab::Today, Tab::Records, Tab::Review];
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
        format!("{self:?}")
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
