//! The app shell: the home at the bottom of the navigation stack and the
//! pages the routes open over it. No page logic here.

use nsh_base::nav_stack;
use nsh_core::prelude::*;

use crate::{
    nav::{self, Route},
    pages::{
        body_profile_page, edit_meal_page, home_page, model_page, new_meal_page, pending_meal_page,
        settings_page,
    },
};

pub fn shell() -> impl IntoElement {
    crate::pages::assets::current::provide();
    nav_stack()
        .flex_1()
        .child(home_page().key("home"))
        .child(each(
            nav::open,
            |route: &Route| route.key(),
            |route, depth| {
                let page = match route.get_untracked() {
                    Route::NewMeal { day, capture } => new_meal_page(day, capture),
                    Route::EditMeal(id) => edit_meal_page(&id),
                    Route::Pending(id) => pending_meal_page(&id),
                    Route::Settings => settings_page(),
                    Route::BodyProfile => body_profile_page(),
                    Route::ModelSettings => model_page(),
                    Route::BackupSettings => crate::pages::settings_backup::backup_page(),
                    Route::Account(name) => crate::pages::assets::account_page(&name, false),
                    Route::AccountCheck(name) => crate::pages::assets::account_page(&name, true),
                    Route::Holding(id) => crate::pages::holdings::holding_page(&id),
                    Route::SavedBatch { id, records } => {
                        crate::pages::receipt::batch_page(id, records)
                    }
                    Route::SavedObservation { record, .. } => {
                        crate::pages::receipt::observation_page(record)
                    }
                    Route::SavedTrade { security, trade } => {
                        crate::pages::holdings::holding_page_with_receipt(&security, Some(trade))
                    }
                    Route::AssetHistory { comparison } => {
                        crate::pages::assets::history_page(comparison)
                    }
                    Route::ClosedHoldings => crate::pages::holdings::closed_page(),
                    Route::Spending {
                        from,
                        to,
                        category,
                        currency,
                    } => crate::pages::finance_review::spending_page(from, to, category, currency),
                    Route::StatementImport => {
                        crate::pages::statement_import::statement_import_page()
                    }
                    Route::PricesAndRates(id) => crate::pages::prices_and_rates::page(id, None),
                    Route::ExchangeRate(currency) => {
                        crate::pages::prices_and_rates::page(None, Some(currency))
                    }
                    Route::HistoricalRate { currency, from, to } => {
                        crate::pages::prices_and_rates::historical_rate(currency, from, to)
                    }
                };
                // Back on iOS and Android is the system's: it pops the page
                // natively, and the routes follow.
                page.on_dismiss(move || nav::truncate(depth.get_untracked()))
            },
        ))
}
