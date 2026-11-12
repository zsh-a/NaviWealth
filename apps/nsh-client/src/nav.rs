//! The navigation stack's state: the pages open over Today, bottom to top.
//! Putting a route in pushes its page; taking it out pops it.

use nsh_core::prelude::*;

use crate::domain::meal::Day;

/// A page over Today.
#[derive(Debug, Clone, PartialEq)]
pub enum Route {
    /// A new meal on `day`, from the picked photo `capture` or by hand.
    NewMeal { day: Day, capture: Option<u64> },
    /// The saved meal with this id.
    EditMeal(String),
    /// The model account and goal.
    Settings,
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
