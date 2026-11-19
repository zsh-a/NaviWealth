//! Confirmed health records. Hosts publish UI state only after these writes
//! succeed, and may pass their own SQLite transaction to the single-row writes.
//! Migration ordering and transactions spanning other domains stay with the host.

use navi_storage::sqlite::{self, Connection, OptionalExtension, params};

use crate::{favorite::Favorite, meal::Meal};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Sql(#[from] sqlite::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error("invalid health record: {0}")]
    Invalid(&'static str),
}

fn meal_row(id: String, day: String, at: i64, body: String) -> Result<Meal, Error> {
    let meal: Meal = serde_json::from_str(&body)?;
    if !meal.is_valid() || meal.id != id || meal.day.to_string() != day || meal.logged_at_ms != at {
        return Err(Error::Invalid("meal body disagrees with its row"));
    }
    Ok(meal)
}

fn favorite_row(id: String, saved: i64, used: i64, body: String) -> Result<Favorite, Error> {
    let favorite: Favorite = serde_json::from_str(&body)?;
    if !favorite.is_valid()
        || favorite.id != id
        || favorite.saved_at_ms != saved
        || favorite.used_at_ms != used
    {
        return Err(Error::Invalid("favorite body disagrees with its row"));
    }
    Ok(favorite)
}

/// Reads the complete inventory; malformed rows are errors, never missing data.
pub fn meals(connection: &Connection) -> Result<Vec<Meal>, Error> {
    let mut statement = connection
        .prepare("SELECT id, day, logged_at_ms, body FROM meals ORDER BY logged_at_ms, id")?;
    let rows = statement.query_map([], |row| {
        Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
    })?;
    rows.map(|row| {
        let (id, day, at, body) = row?;
        meal_row(id, day, at, body)
    })
    .collect()
}

/// One validated write, also usable inside a host-owned cross-domain transaction.
pub fn save_meal(connection: &Connection, meal: &Meal) -> Result<(), Error> {
    write_meal(connection, meal, true)
}

/// Recognition confirmation creates a new identity and must never overwrite
/// an already confirmed record. Accepts a host-owned transaction.
pub fn insert_meal(connection: &Connection, meal: &Meal) -> Result<(), Error> {
    write_meal(connection, meal, false)
}

fn write_meal(connection: &Connection, meal: &Meal, replace: bool) -> Result<(), Error> {
    if !meal.is_valid() {
        return Err(Error::Invalid("meal"));
    }
    let body = serde_json::to_string(meal)?;
    let sql = if replace {
        "INSERT INTO meals (id, day, logged_at_ms, body) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (id) DO UPDATE SET day=excluded.day, logged_at_ms=excluded.logged_at_ms, body=excluded.body"
    } else {
        "INSERT INTO meals (id, day, logged_at_ms, body) VALUES (?1, ?2, ?3, ?4)"
    };
    connection.execute(
        sql,
        params![meal.id, meal.day.to_string(), meal.logged_at_ms, body],
    )?;
    Ok(())
}

/// Moves the legacy inventory atomically, preserving records already in SQLite.
pub fn import_legacy_meals(connection: &Connection, meals: &[Meal]) -> Result<(), Error> {
    let tx = connection.unchecked_transaction()?;
    for meal in meals {
        if !meal.is_valid() {
            return Err(Error::Invalid("legacy meal"));
        }
        tx.execute(
            "INSERT OR IGNORE INTO meals (id, day, logged_at_ms, body) VALUES (?1, ?2, ?3, ?4)",
            params![
                meal.id,
                meal.day.to_string(),
                meal.logged_at_ms,
                serde_json::to_string(meal)?
            ],
        )?;
    }
    tx.commit()?;
    Ok(())
}

/// Removes and returns the committed record for Undo. Validation failure leaves it intact.
pub fn remove_meal(connection: &Connection, id: &str) -> Result<Option<Meal>, Error> {
    let tx = connection.unchecked_transaction()?;
    let raw = tx
        .query_row(
            "SELECT id, day, logged_at_ms, body FROM meals WHERE id=?1",
            [id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()?;
    let Some((id, day, at, body)) = raw else {
        return Ok(None);
    };
    let removed = meal_row(id, day, at, body)?;
    tx.execute("DELETE FROM meals WHERE id=?1", [&removed.id])?;
    tx.commit()?;
    Ok(Some(removed))
}

pub fn favorites(connection: &Connection) -> Result<Vec<Favorite>, Error> {
    let mut statement =
        connection.prepare("SELECT id, saved_at_ms, used_at_ms, body FROM saved_meals")?;
    let rows = statement.query_map([], |row| {
        Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
    })?;
    rows.map(|row| {
        let (id, saved, used, body) = row?;
        favorite_row(id, saved, used, body)
    })
    .collect()
}

pub fn save_favorite(connection: &Connection, favorite: &Favorite) -> Result<(), Error> {
    if !favorite.is_valid() {
        return Err(Error::Invalid("favorite"));
    }
    let body = serde_json::to_string(favorite)?;
    connection.execute(
        "INSERT INTO saved_meals (id, saved_at_ms, used_at_ms, body) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (id) DO UPDATE SET saved_at_ms=excluded.saved_at_ms, used_at_ms=excluded.used_at_ms, body=excluded.body",
        params![favorite.id, favorite.saved_at_ms, favorite.used_at_ms, body],
    )?;
    Ok(())
}

pub fn remove_favorite(connection: &Connection, id: &str) -> Result<Option<Favorite>, Error> {
    let tx = connection.unchecked_transaction()?;
    let raw = tx
        .query_row(
            "SELECT id, saved_at_ms, used_at_ms, body FROM saved_meals WHERE id=?1",
            [id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()?;
    let Some((id, saved, used, body)) = raw else {
        return Ok(None);
    };
    let removed = favorite_row(id, saved, used, body)?;
    tx.execute("DELETE FROM saved_meals WHERE id=?1", [&removed.id])?;
    tx.commit()?;
    Ok(Some(removed))
}

/// The new meal and favorite's last-use time commit together.
pub fn log_favorite(
    connection: &Connection,
    favorite: &Favorite,
    meal: &Meal,
) -> Result<(), Error> {
    let tx = connection.unchecked_transaction()?;
    let exists: bool = tx.query_row(
        "SELECT EXISTS(SELECT 1 FROM saved_meals WHERE id=?1)",
        [&favorite.id],
        |row| row.get(0),
    )?;
    if !exists {
        return Err(Error::Invalid("favorite no longer exists"));
    }
    insert_meal(&tx, meal)?;
    save_favorite(&tx, favorite)?;
    tx.commit()?;
    Ok(())
}

/// The same health contracts used by normal loads and backup validation.
pub fn validate(connection: &Connection) -> Result<(), Error> {
    meals(connection)?;
    favorites(connection)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        meal::MealSlot,
        nutrition::{Food, FoodSource, Nutrients},
    };

    fn database() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch("CREATE TABLE meals(id TEXT PRIMARY KEY,day TEXT NOT NULL,logged_at_ms INTEGER NOT NULL,body TEXT NOT NULL);
                         CREATE TABLE saved_meals(id TEXT PRIMARY KEY,saved_at_ms INTEGER NOT NULL,used_at_ms INTEGER NOT NULL,body TEXT NOT NULL);").unwrap();
        c
    }
    fn meal(id: &str) -> Meal {
        Meal {
            id: id.into(),
            day: "2026-11-19".parse().unwrap(),
            logged_at_ms: 1,
            slot: MealSlot::Lunch,
            title: None,
            foods: vec![Food {
                id: 1,
                name: "Rice".into(),
                grams: 100.0,
                per_100g: Nutrients::new(130.0, 2.0, 28.0, 1.0),
                source: FoodSource::Manual,
                confidence: None,
                estimated_grams: None,
            }],
            photo: None,
            model: None,
            prompt_version: None,
        }
    }
    fn favorite() -> Favorite {
        Favorite::from_meal(&meal("source"), "favorite".into(), None, 1)
    }

    #[test]
    fn records_round_trip_and_removal_returns_only_committed_rows() {
        let c = database();
        let kept = meal("kept");
        let f = favorite();
        save_meal(&c, &kept).unwrap();
        save_favorite(&c, &f).unwrap();
        assert_eq!(meals(&c).unwrap().as_slice(), std::slice::from_ref(&kept));
        assert_eq!(favorites(&c).unwrap().as_slice(), std::slice::from_ref(&f));
        validate(&c).unwrap();
        c.execute_batch("CREATE TRIGGER fail_delete BEFORE DELETE ON meals BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
        assert!(remove_meal(&c, "kept").is_err());
        assert_eq!(meals(&c).unwrap().as_slice(), std::slice::from_ref(&kept));
        c.execute_batch("DROP TRIGGER fail_delete;").unwrap();
        assert_eq!(remove_meal(&c, "kept").unwrap(), Some(kept));
        assert_eq!(remove_meal(&c, "kept").unwrap(), None);
        assert_eq!(remove_favorite(&c, "favorite").unwrap(), Some(f));
        assert!(favorites(&c).unwrap().is_empty());
    }

    #[test]
    fn new_confirmation_cannot_overwrite_an_existing_identity() {
        let c = database();
        let kept = meal("same-id");
        insert_meal(&c, &kept).unwrap();
        let mut changed = kept.clone();
        changed.foods[0].grams = 200.0;
        assert!(insert_meal(&c, &changed).is_err());
        assert_eq!(meals(&c).unwrap(), vec![kept]);
    }

    #[test]
    fn malformed_rows_and_disagreeing_metadata_are_errors_without_data_loss() {
        let c = database();
        save_meal(&c, &meal("kept")).unwrap();
        c.execute("UPDATE meals SET day='2026-11-18'", []).unwrap();
        assert!(meals(&c).is_err());
        assert!(remove_meal(&c, "kept").is_err());
        assert_eq!(
            c.query_row("SELECT count(*) FROM meals", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
        c.execute("UPDATE meals SET day='2026-11-19'", []).unwrap();
        save_favorite(&c, &favorite()).unwrap();
        c.execute("UPDATE saved_meals SET used_at_ms=2", [])
            .unwrap();
        assert!(validate(&c).is_err());
        assert!(remove_favorite(&c, "favorite").is_err());
        c.execute("UPDATE saved_meals SET used_at_ms=1,body='not json'", [])
            .unwrap();
        assert!(favorites(&c).is_err());
    }

    #[test]
    fn failed_favorite_logging_rolls_back_the_meal_and_last_use_together() {
        let c = database();
        let mut f = favorite();
        save_favorite(&c, &f).unwrap();
        f.used_at_ms = 2;
        c.execute_batch("CREATE TRIGGER fail_update BEFORE UPDATE ON saved_meals BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
        assert!(log_favorite(&c, &f, &meal("new")).is_err());
        assert!(meals(&c).unwrap().is_empty());
        assert_eq!(favorites(&c).unwrap()[0].used_at_ms, 1);
        c.execute_batch("DROP TRIGGER fail_update;").unwrap();
        log_favorite(&c, &f, &meal("new")).unwrap();
        assert_eq!(meals(&c).unwrap().len(), 1);
        assert_eq!(favorites(&c).unwrap()[0].used_at_ms, 2);
    }

    #[test]
    fn legacy_import_preserves_existing_rows_and_rolls_back_invalid_batches() {
        let c = database();
        let kept = meal("kept");
        save_meal(&c, &kept).unwrap();
        let mut changed = kept.clone();
        changed.logged_at_ms = 2;
        import_legacy_meals(&c, &[changed, meal("new")]).unwrap();
        assert_eq!(meals(&c).unwrap()[0], kept);
        let mut invalid = meal("invalid");
        invalid.foods.clear();
        assert!(save_meal(&c, &invalid).is_err());
        assert!(import_legacy_meals(&c, &[meal("rolled-back"), invalid]).is_err());
        assert_eq!(meals(&c).unwrap().len(), 2);
    }
}
