//! App composition state: database + services wiring. This is the
//! composition root for the client — it may import multiple domains and
//! infrastructure, everything below it stays layered.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock, RwLock};

use lifeos::Result as LifeosResult;
use lifeos::backup::{self, RestoreReport};
use lifeos::db::Db;
use lifeos::db::settings;
use lifeos::key_store::{FileKeyStore, KeyStore};
use lifeos::money::Currency;
use lifeos::sync::auth::AuthClient;
use lifeos::sync::auth::AuthSession;
use lifeos::sync::{
    MutationStamper, SettingsTokenProvider, SyncEngine, SyncOutcome, SyncRegistry, ensure_identity,
    outbox,
};
use naviwealth_finance::models::{Account, NewAccount};
use naviwealth_finance::repos::account_repository::{self, AccountBalance};
use naviwealth_finance::repos::journal_repository::{self, EntryWithPostings};
use naviwealth_finance::repos::settings_repository;
use naviwealth_finance::system_accounts;
use naviwealth_finance::tables;
use nsh_core::prelude::*;
use rust_decimal::Decimal;

use crate::ai::LlmProfile;

pub const APP_ID: &str = "com.naviwealth.client";

/// Shared data-version bump: screens watch it and reload when any write
/// lands (the tab screens stay mounted, so they need the nudge).
#[derive(Clone, Copy)]
pub struct DataVersion(pub Signal<u64>);
pub const DEFAULT_BASE_URL: &str = "http://127.0.0.1:8787";

const OWNER_KEY: &str = "sync.owner_user_id";
const DEVICE_KEY: &str = "sync.device_id";
const BASE_URL_KEY: &str = "sync.base_url";
const LOCAL_OWNER: &str = "local";

static TEST_MODE: AtomicBool = AtomicBool::new(false);
static SERVICES: OnceLock<Arc<Services>> = OnceLock::new();

/// Headless UI tests run the whole app with an in-memory database, no
/// encryption and the mock AI provider. Must be called before
/// [`Services::shared`].
pub fn enable_test_mode() {
    TEST_MODE.store(true, Ordering::SeqCst);
}

pub fn is_test_mode() -> bool {
    TEST_MODE.load(Ordering::SeqCst)
}

pub struct Services {
    pub db: Db,
    pub runtime: tokio::runtime::Runtime,
    pub registry: SyncRegistry,
    pub device_id: String,
    pub encrypted: bool,
    pub app_dir: Option<PathBuf>,
    owner: RwLock<String>,
}

/// The shared write path: validate the balance invariant, then commit the
/// entry, its postings and their outbox pointers in one transaction.
fn write_entry(
    conn: &mut rusqlite::Connection,
    stamper: &MutationStamper,
    build: naviwealth_finance::builders::EntryBuild,
) -> LifeosResult<()> {
    let base = settings_repository::base_currency(conn)?;
    let fx = |conn: &rusqlite::Connection, from: &str, to: &str, as_of: i64| {
        naviwealth_finance::fx::rate_at(conn, from, to, as_of)
    };
    journal_repository::create(conn, stamper, &fx, &base, build)?;
    Ok(())
}

impl Services {
    /// Process-wide services, initialized once.
    pub fn shared() -> Arc<Self> {
        SERVICES
            .get_or_init(|| Self::init().expect("services init"))
            .clone()
    }

    fn init() -> LifeosResult<Arc<Self>> {
        let test = is_test_mode();
        let migrations = lifeos::db::migrations::core_migrations().push(tables::migration());

        let (db, encrypted, app_dir) = if test {
            (
                Db::open(lifeos::db::DbOpenOptions {
                    path: PathBuf::from(":memory:"),
                    encryption_key: None,
                    migrations,
                })?,
                false,
                None,
            )
        } else {
            let dir = lifeos_platform::app_data_dir(APP_ID);
            std::fs::create_dir_all(&dir)?;
            // SQLCipher master key lives in the platform key store
            // (desktop fallback: file key store under the app dir).
            let key_store = FileKeyStore::new(dir.join("keys"));
            let key = match key_store.get_key(backup::DATABASE_KEY_ID)? {
                Some(key) => key,
                None => {
                    let key = new_database_key();
                    key_store.set_key(backup::DATABASE_KEY_ID, &key)?;
                    key
                }
            };
            (
                Db::open(lifeos::db::DbOpenOptions {
                    path: dir.join("naviwealth.db"),
                    encryption_key: Some(key),
                    migrations,
                })?,
                true,
                Some(dir),
            )
        };

        let registry = tables::sync_registry();
        let device_id = {
            let stored = db
                .call_sync(|conn| settings::get_setting(conn, DEVICE_KEY))?
                .filter(|v| !v.is_empty());
            stored.unwrap_or_else(lifeos::ids::new_id)
        };
        let owner = db
            .call_sync(|conn| settings::get_setting(conn, OWNER_KEY))?
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| LOCAL_OWNER.to_owned());

        // First-run bootstrap: identity, system account tree, base
        // currency. Idempotent.
        {
            let device_id = device_id.clone();
            let owner_for_init = owner.clone();
            db.call_sync(move |conn| {
                ensure_identity(conn, &owner_for_init, &device_id)?;
                let stamper = MutationStamper::new(&owner_for_init, &device_id);
                if account_repository::find_system_account(
                    conn,
                    &owner_for_init,
                    "equity:openingBalance",
                )?
                .is_none()
                {
                    system_accounts::seed_system_accounts(conn, &stamper)?;
                }
                if settings::get_setting(conn, settings_repository::BASE_CURRENCY_KEY)?.is_none() {
                    settings_repository::set_base_currency(conn, "CNY")?;
                }
                if settings::get_setting(conn, BASE_URL_KEY)?.is_none() {
                    settings::set_setting(conn, BASE_URL_KEY, DEFAULT_BASE_URL)?;
                }
                Ok(())
            })?;
        }

        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()?;

        Ok(Arc::new(Self {
            db,
            runtime,
            registry,
            device_id,
            encrypted,
            app_dir,
            owner: RwLock::new(owner),
        }))
    }

    pub fn owner(&self) -> String {
        self.owner.read().unwrap().clone()
    }

    /// The stamper for local mutations; built per call so an owner change
    /// (login) takes effect immediately.
    pub fn stamper(&self) -> MutationStamper {
        MutationStamper::new(self.owner(), self.device_id.clone())
    }

    /// Bind the local data space to a backend user. Seeds the new owner's
    /// system tree when it does not exist yet.
    pub fn bind_owner(&self, user_id: &str) -> LifeosResult<()> {
        *self.owner.write().unwrap() = user_id.to_owned();
        let owner = user_id.to_owned();
        let device_id = self.device_id.clone();
        self.db.call_sync(move |conn| {
            ensure_identity(conn, &owner, &device_id)?;
            if account_repository::find_system_account(conn, &owner, "equity:openingBalance")?
                .is_none()
            {
                let stamper = MutationStamper::new(&owner, &device_id);
                system_accounts::seed_system_accounts(conn, &stamper)?;
            }
            Ok(())
        })
    }

    // ---- Settings ----

    pub async fn settings_get(&self, key: &str) -> Option<String> {
        let key = key.to_owned();
        self.db
            .call(move |conn| settings::get_setting(conn, &key))
            .await
            .ok()
            .flatten()
    }

    pub async fn settings_set(&self, key: &str, value: &str) {
        let key = key.to_owned();
        let value = value.to_owned();
        let _ = self
            .db
            .call(move |conn| settings::set_setting(conn, &key, &value))
            .await;
    }

    pub async fn base_url(&self) -> String {
        self.settings_get(BASE_URL_KEY)
            .await
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| DEFAULT_BASE_URL.to_owned())
    }

    // ---- Finance reads (UI-facing, errors as strings) ----

    pub async fn accounts_with_balances(
        &self,
    ) -> Result<Vec<(Account, Option<AccountBalance>)>, String> {
        self.db
            .call(|conn| {
                let accounts =
                    account_repository::list(conn, false).map_err(lifeos::LifeosError::from)?;
                let balances = account_repository::balances(conn)?;
                Ok(accounts
                    .into_iter()
                    .map(|account| {
                        let balance = balances
                            .iter()
                            .find(|b| b.account_id == account.id)
                            .cloned();
                        (account, balance)
                    })
                    .collect())
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn recent_entries(&self, limit: i64) -> Result<Vec<EntryWithPostings>, String> {
        self.db
            .call(move |conn| {
                journal_repository::list_recent(conn, limit).map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn account_names(&self) -> Result<Vec<(String, String)>, String> {
        self.db
            .call(|conn| {
                Ok(account_repository::list(conn, true)
                    .map_err(lifeos::LifeosError::from)?
                    .into_iter()
                    .map(|a| (a.id, a.name))
                    .collect())
            })
            .await
            .map_err(|e| e.to_string())
    }

    /// Cash-class accounts for the record form: (id, name, currency).
    pub async fn cash_accounts(&self) -> Result<Vec<(String, String, String)>, String> {
        self.db
            .call(|conn| {
                Ok(account_repository::list_cash_accounts(conn)
                    .map_err(lifeos::LifeosError::from)?
                    .into_iter()
                    .map(|a| (a.id, a.name, a.currency))
                    .collect())
            })
            .await
            .map_err(|e| e.to_string())
    }

    /// User-facing expense categories: (ledger account id, display name).
    pub async fn expense_categories(&self) -> Result<Vec<(String, String)>, String> {
        self.db
            .call(|conn| {
                let mut stmt = conn.prepare_cached(
                    r#"SELECT c.ledger_account_id, c.name, c.name_override FROM "fin:categories" c
                     JOIN "fin:accounts" a ON a.id = c.ledger_account_id
                     WHERE c.deleted_at IS NULL AND c.archived = 0
                     ORDER BY c.sort_order"#,
                )?;
                let rows = stmt.query_map([], |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, Option<String>>(2)?,
                    ))
                })?;
                let mut out = Vec::new();
                for row in rows {
                    let (id, name, name_override) = row?;
                    let display = system_accounts::category_display_name(
                        &name,
                        name_override.as_deref(),
                        true,
                    );
                    out.push((id, display.to_owned()));
                }
                Ok(out)
            })
            .await
            .map_err(|e| e.to_string())
    }

    // ---- Finance writes ----

    pub async fn create_account(
        &self,
        new: NewAccount,
        opening_amount: Option<Decimal>,
    ) -> Result<Account, String> {
        Currency::new(&new.currency).map_err(|e| e.to_string())?;
        let stamper = self.stamper();
        self.db
            .call(move |conn| {
                let account = account_repository::create(conn, &stamper, new)?;
                if let Some(amount) = opening_amount
                    && amount != Decimal::ZERO
                {
                    let owner = stamper.owner_user_id.clone();
                    let equity = account_repository::find_system_account(
                        conn,
                        &owner,
                        "equity:openingBalance",
                    )?
                    .ok_or_else(|| {
                        naviwealth_finance::FinanceError::InvalidData(
                            "equity:openingBalance seed missing".into(),
                        )
                    })?;
                    let build = naviwealth_finance::builders::opening_balance(
                        lifeos::ids::now_secs(),
                        account.id.clone(),
                        equity.id,
                        amount,
                        &account.currency,
                        None,
                        None,
                        vec![],
                    )?;
                    write_entry(conn, &stamper, build)?;
                }
                Ok(account)
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn create_expense(
        &self,
        date: i64,
        amount: Decimal,
        expense_account_id: String,
        from_account_id: String,
        payee: Option<String>,
        narration: Option<String>,
    ) -> Result<(), String> {
        let stamper = self.stamper();
        self.db
            .call(move |conn| {
                let from = account_repository::get_required(conn, &from_account_id)?;
                let build = naviwealth_finance::builders::expense(
                    date,
                    expense_account_id,
                    from.id,
                    amount,
                    &from.currency,
                    payee,
                    narration.as_deref(),
                    None,
                    vec![],
                )?;
                write_entry(conn, &stamper, build)?;
                Ok(())
            })
            .await
            .map_err(|e| e.to_string())
    }

    // ---- Sync ----

    pub async fn outbox_count(&self) -> LifeosResult<i64> {
        self.db.call(|conn| outbox::count(conn)).await
    }

    /// Run one sync cycle with the current settings.
    pub async fn sync_now(&self) -> LifeosResult<SyncOutcome> {
        let base_url = self.base_url().await;
        let transport: Arc<dyn lifeos::sync::SyncTransport> =
            Arc::new(lifeos::sync::transport::HttpSyncTransport::new(base_url)?);
        let auth = Arc::new(SettingsTokenProvider::new(self.db.clone()));
        let engine = SyncEngine::new(
            self.db.clone(),
            self.registry.clone(),
            transport,
            auth,
            self.stamper(),
        );
        engine.sync_once().await
    }

    // ---- Auth ----

    pub async fn register(
        &self,
        base_url: &str,
        email: &str,
        password: &str,
    ) -> Result<(), String> {
        let client = AuthClient::new(base_url).map_err(|e| e.to_string())?;
        let session = client
            .register(&lifeos::sync::auth::RegisterRequest {
                email: email.to_owned(),
                password: password.to_owned(),
                domains: vec!["finance".to_owned()],
                device_name: Some("naviwealth-client".to_owned()),
                device_id: Some(self.device_id.clone()),
            })
            .await
            .map_err(|e| e.to_string())?;
        self.store_session(session).await
    }

    pub async fn login(&self, base_url: &str, email: &str, password: &str) -> Result<(), String> {
        let client = AuthClient::new(base_url).map_err(|e| e.to_string())?;
        let session = client
            .login(&lifeos::sync::auth::LoginRequest {
                email: email.to_owned(),
                password: password.to_owned(),
                domains: vec!["finance".to_owned()],
            })
            .await
            .map_err(|e| e.to_string())?;
        self.store_session(session).await
    }

    async fn store_session(&self, session: AuthSession) -> Result<(), String> {
        let user_id = session.user_id.clone();
        self.db
            .call(move |conn| {
                settings::set_setting(conn, "sync.access_token", &session.access_token)?;
                settings::set_setting(conn, "sync.user_id", &user_id)?;
                settings::set_setting(conn, "sync.expires_at", &session.expires_at.to_string())?;
                Ok(())
            })
            .await
            .map_err(|e| e.to_string())?;
        self.bind_owner(&session.user_id)
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub async fn auth_status(&self) -> (Option<String>, String) {
        let user = self.settings_get("sync.user_id").await;
        (user, self.owner())
    }

    // ---- Backup ----

    pub async fn backup_export(&self, path: PathBuf, passphrase: String) -> Result<String, String> {
        let registry = self.registry.clone();
        let payload = self
            .db
            .call(move |conn| {
                backup::export_payload(&registry, conn, None, chrono::Utc::now().to_rfc3339())
            })
            .await
            .map_err(|e| e.to_string())?;
        let json =
            lifeos::backup::encrypt_payload(&payload, &passphrase).map_err(|e| e.to_string())?;
        let written = path.to_string_lossy().into_owned();
        tokio::task::spawn_blocking(move || std::fs::write(&path, json))
            .await
            .map_err(|e| e.to_string())?
            .map_err(|e| e.to_string())?;
        Ok(written)
    }

    pub async fn backup_import(
        &self,
        path: PathBuf,
        passphrase: String,
    ) -> Result<RestoreReport, String> {
        let json = tokio::task::spawn_blocking(move || std::fs::read_to_string(&path))
            .await
            .map_err(|e| e.to_string())?
            .map_err(|e| e.to_string())?;
        let payload =
            lifeos::backup::decrypt_payload(&json, &passphrase).map_err(|e| e.to_string())?;
        let registry = self.registry.clone();
        self.db
            .call(move |conn| backup::restore_payload(&registry, conn, &payload))
            .await
            .map_err(|e| e.to_string())
    }

    // ---- AI profile ----

    pub async fn llm_profile(&self) -> Option<LlmProfile> {
        let raw = self.settings_get("ai.llm_profile").await?;
        serde_json::from_str(&raw).ok()
    }

    pub async fn save_llm_profile(&self, profile: LlmProfile) {
        let raw = serde_json::to_string(&profile).unwrap_or_default();
        self.settings_set("ai.llm_profile", &raw).await;
    }
}

/// 32 random bytes for the database master key (two UUIDv4s = 244 random
/// bits from the OS CSPRNG via the uuid crate).
fn new_database_key() -> Vec<u8> {
    let mut bytes = Vec::with_capacity(32);
    bytes.extend_from_slice(uuid::Uuid::new_v4().as_bytes());
    bytes.extend_from_slice(uuid::Uuid::new_v4().as_bytes());
    bytes
}
