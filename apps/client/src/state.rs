//! App composition state: database + services wiring. This is the
//! composition root for the client — it may import multiple domains and
//! infrastructure, everything below it stays layered.

use std::collections::BTreeSet;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, RwLock};

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
use nsh_core::prelude::*;
use rust_decimal::Decimal;

use crate::ai::LlmProfile;
use crate::domains;

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
static SERVICES: Mutex<Option<Arc<Services>>> = Mutex::new(None);

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
    pub device_id: String,
    pub encrypted: bool,
    pub app_dir: Option<PathBuf>,
    owner: RwLock<String>,
    /// The opt-in domains currently switched on (mirrors the settings KV).
    enabled_domains: RwLock<BTreeSet<&'static str>>,
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
        Self::try_shared().expect("services init")
    }

    /// Cache only successful initialization so the startup screen can retry.
    pub fn try_shared() -> Result<Arc<Self>, String> {
        let mut services = SERVICES.lock().map_err(|_| "startup lock poisoned")?;
        if let Some(services) = services.as_ref() {
            return Ok(services.clone());
        }
        log::info!("startup: initializing local services");
        match Self::init() {
            Ok(initialized) => {
                log::info!("startup: local services ready");
                *services = Some(initialized.clone());
                Ok(initialized)
            }
            Err(error) => {
                log::error!("startup: local services failed: {error}");
                Err(error.to_string())
            }
        }
    }

    fn init() -> LifeosResult<Arc<Self>> {
        let dir = if is_test_mode() {
            None
        } else {
            Some(lifeos_platform::app_data_dir(APP_ID)?)
        };
        Self::init_at(dir)
    }

    fn init_at(dir: Option<PathBuf>) -> LifeosResult<Arc<Self>> {
        let migrations = domains::domain_migrations();

        let (db, encrypted, app_dir) = if let Some(dir) = dir {
            std::fs::create_dir_all(&dir)?;
            // The current adapter keeps the SQLCipher key in an app-private
            // file. Keychain/Keystore wrapping remains a separate platform task.
            log::info!("startup: private data directory ready");
            let key_store = FileKeyStore::new(dir.join("keys"));
            let key = match key_store.get_key(backup::DATABASE_KEY_ID)? {
                Some(key) => key,
                None => {
                    let key = new_database_key();
                    key_store.set_key(backup::DATABASE_KEY_ID, &key)?;
                    key
                }
            };
            log::info!("startup: opening encrypted database");
            (
                Db::open(lifeos::db::DbOpenOptions {
                    path: dir.join("naviwealth.db"),
                    encryption_key: Some(key),
                    migrations,
                })?,
                true,
                Some(dir),
            )
        } else {
            (
                Db::open(lifeos::db::DbOpenOptions {
                    path: PathBuf::from(":memory:"),
                    encryption_key: None,
                    migrations,
                })?,
                false,
                None,
            )
        };

        log::info!("startup: database and migrations ready");
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

        // Opt-in domains: read the switches once (finance is not here — it
        // is always on and never in this set).
        let mut enabled_domains = BTreeSet::new();
        for spec in domains::OPTIONAL_DOMAINS {
            let on = db
                .call_sync(|conn| settings::get_setting(conn, spec.enabled_key))?
                .as_deref()
                == Some("1");
            if on {
                enabled_domains.insert(spec.key);
            }
        }

        // First-run bootstrap: identity, system account tree, base
        // currency. Idempotent.
        {
            let device_id = device_id.clone();
            let owner_for_init = owner.clone();
            db.call_sync(move |conn| {
                ensure_identity(conn, &owner_for_init, &device_id)?;
                naviwealth_finance::wealth::rebuild_manual_fx(conn, &owner_for_init)?;
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
            device_id,
            encrypted,
            app_dir,
            owner: RwLock::new(owner),
            enabled_domains: RwLock::new(enabled_domains),
        }))
    }

    pub fn owner(&self) -> String {
        self.owner.read().unwrap().clone()
    }

    // ---- Opt-in domains ----

    /// The enabled domain keys (finance is not in the set — always on).
    pub fn enabled_domain_keys(&self) -> Vec<&'static str> {
        self.enabled_domains
            .read()
            .unwrap()
            .iter()
            .copied()
            .collect()
    }

    pub fn domain_enabled(&self, key: &str) -> bool {
        self.enabled_domains.read().unwrap().contains(key)
    }

    /// Flip the in-memory switch (the settings KV write happens next to it
    /// via [`crate::domains::set_enabled`]).
    pub fn set_domain_enabled(&self, key: &'static str, on: bool) {
        let mut domains = self.enabled_domains.write().unwrap();
        if on {
            domains.insert(key);
        } else {
            domains.remove(key);
        }
    }

    /// The registry matching the current domain switches (sync + AI use
    /// only the active domains' row families).
    pub fn sync_registry(&self) -> SyncRegistry {
        domains::sync_registry_for(&self.enabled_domain_keys())
    }

    /// Every registered row family (backup/restore must round-trip data of
    /// disabled domains too).
    pub fn full_registry(&self) -> SyncRegistry {
        domains::full_sync_registry()
    }

    /// The stamper for local mutations; built per call so an owner change
    /// (login) takes effect immediately.
    pub fn stamper(&self) -> MutationStamper {
        MutationStamper::new(self.owner(), self.device_id.clone())
    }

    /// Bind a first local data space to an account without hiding its records.
    pub fn bind_owner(&self, user_id: &str) -> LifeosResult<()> {
        let previous = self.owner();
        let owner = user_id.to_owned();
        let registry = self.full_registry();
        let device_id = self.device_id.clone();
        self.db.call_sync(move |conn| {
            let tx = conn.savepoint()?;
            adopt_local_owner(&tx, &registry, &previous, &owner, &device_id)?;
            ensure_identity(&tx, &owner, &device_id)?;
            naviwealth_finance::wealth::rebuild_manual_fx(&tx, &owner)?;
            tx.commit()?;
            Ok(())
        })?;
        *self.owner.write().unwrap() = user_id.to_owned();
        Ok(())
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
                in_savepoint(conn, |conn| {
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
                            chrono::Local::now()
                                .date_naive()
                                .and_hms_opt(0, 0, 0)
                                .expect("midnight")
                                .and_utc()
                                .timestamp(),
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
                naviwealth_finance::daily::save(
                    conn,
                    &stamper,
                    None,
                    &naviwealth_finance::daily::RecordDraft {
                        kind: naviwealth_finance::daily::RecordKind::Expense,
                        date,
                        amount,
                        account_id: from_account_id,
                        category_id: Some(expense_account_id),
                        destination_account_id: None,
                        destination_amount: None,
                        payee,
                        note: narration,
                    },
                )
                .map_err(lifeos::LifeosError::from)?;
                Ok(())
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn outbox_count(&self) -> LifeosResult<i64> {
        self.db.call(|conn| outbox::count(conn)).await
    }

    /// Run one sync cycle with the current settings.
    pub async fn sync_now(&self) -> LifeosResult<SyncOutcome> {
        let base_url = self.base_url().await;
        let token = self
            .settings_get("sync.access_token")
            .await
            .filter(|token| !token.is_empty())
            .ok_or_else(|| lifeos::LifeosError::Auth("请先登录后再同步".to_owned()))?;
        let expires_at = self
            .settings_get("sync.expires_at")
            .await
            .and_then(|value| value.parse::<i64>().ok())
            .unwrap_or(0);
        let now = lifeos::ids::now_secs();
        if expires_at <= now {
            return Err(lifeos::LifeosError::Auth(
                "登录已过期，请重新登录".to_owned(),
            ));
        }
        let domains = self.auth_domains();
        let domains_json = serde_json::to_string(&domains)?;
        if expires_at <= now + 300
            || self.settings_get("sync.domains").await.as_deref() != Some(&domains_json)
        {
            let refreshed = AuthClient::new(&base_url)?
                .refresh(&token, &lifeos::sync::auth::RefreshRequest { domains })
                .await?;
            let domains_json = domains_json.clone();
            self.db
                .call(move |conn| {
                    let tx = conn.savepoint()?;
                    settings::set_setting(&tx, "sync.access_token", &refreshed.access_token)?;
                    settings::set_setting(
                        &tx,
                        "sync.expires_at",
                        &refreshed.expires_at.to_string(),
                    )?;
                    settings::set_setting(&tx, "sync.domains", &domains_json)?;
                    tx.commit()?;
                    Ok(())
                })
                .await?;
        }
        let transport: Arc<dyn lifeos::sync::SyncTransport> =
            Arc::new(lifeos::sync::transport::HttpSyncTransport::new(base_url)?);
        let auth = Arc::new(SettingsTokenProvider::new(self.db.clone()));
        let engine = SyncEngine::new(
            self.db.clone(),
            self.sync_registry(),
            transport,
            auth,
            self.stamper(),
        );
        let result = engine.sync_once().await?;
        let owner = self.owner();
        self.db
            .call(move |conn| {
                naviwealth_finance::wealth::rebuild_manual_fx(conn, &owner)?;
                Ok(())
            })
            .await?;
        Ok(result)
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
                domains: self.auth_domains(),
                device_name: Some("naviwealth-client".to_owned()),
                device_id: Some(self.device_id.clone()),
            })
            .await
            .map_err(|e| e.to_string())?;
        self.store_session(session, base_url).await
    }

    pub async fn login(&self, base_url: &str, email: &str, password: &str) -> Result<(), String> {
        let client = AuthClient::new(base_url).map_err(|e| e.to_string())?;
        let session = client
            .login(&lifeos::sync::auth::LoginRequest {
                email: email.to_owned(),
                password: password.to_owned(),
                domains: self.auth_domains(),
                device_name: Some("NaviWealth".to_owned()),
                device_id: Some(self.device_id.clone()),
            })
            .await
            .map_err(|e| e.to_string())?;
        self.store_session(session, base_url).await
    }

    fn auth_domains(&self) -> Vec<String> {
        std::iter::once("finance".to_owned())
            .chain(self.enabled_domain_keys().into_iter().map(str::to_owned))
            .collect()
    }

    async fn store_session(&self, session: AuthSession, base_url: &str) -> Result<(), String> {
        if session.device_id != self.device_id {
            return Err("服务器返回的设备身份不匹配，请重新登录".to_owned());
        }
        if session.user_id.trim().is_empty()
            || session.access_token.is_empty()
            || !session.token_type.eq_ignore_ascii_case("bearer")
            || session.expires_at <= lifeos::ids::now_secs()
        {
            return Err("服务器返回的登录信息无效".to_owned());
        }
        let previous = self.owner();
        let user_id = session.user_id.clone();
        let owner = user_id.clone();
        let registry = self.full_registry();
        let base_url = base_url.trim().trim_end_matches('/').to_owned();
        let device_id = self.device_id.clone();
        let domains_json =
            serde_json::to_string(&self.auth_domains()).map_err(|e| e.to_string())?;
        self.db
            .call(move |conn| {
                let tx = conn.savepoint()?;
                adopt_local_owner(&tx, &registry, &previous, &user_id, &device_id)?;
                ensure_identity(&tx, &user_id, &device_id)?;
                naviwealth_finance::wealth::rebuild_manual_fx(&tx, &user_id)?;
                settings::set_setting(&tx, "sync.access_token", &session.access_token)?;
                settings::set_setting(&tx, "sync.user_id", &user_id)?;
                settings::set_setting(&tx, "sync.expires_at", &session.expires_at.to_string())?;
                settings::set_setting(&tx, BASE_URL_KEY, &base_url)?;
                settings::set_setting(&tx, "sync.domains", &domains_json)?;
                tx.commit()?;
                Ok(())
            })
            .await
            .map_err(|e| e.to_string())?;
        *self.owner.write().unwrap() = owner;
        Ok(())
    }

    pub async fn auth_status(&self) -> (Option<String>, String) {
        let user = self.settings_get("sync.user_id").await;
        (user, self.owner())
    }

    // ---- Backup ----

    pub async fn backup_export(&self, path: PathBuf, passphrase: String) -> Result<String, String> {
        if passphrase.trim().is_empty() {
            return Err("请输入备份口令".to_owned());
        }
        let registry = self.full_registry();
        let payload = self
            .db
            .call(move |conn| {
                let mut payload =
                    backup::export_payload(&registry, conn, None, chrono::Utc::now().to_rfc3339())?;
                for key in backup_preference_keys() {
                    let value = settings::get_setting(conn, key)?.unwrap_or_else(|| {
                        if key == settings_repository::BASE_CURRENCY_KEY {
                            "CNY"
                        } else {
                            "0"
                        }
                        .to_owned()
                    });
                    payload.preferences.insert(key.to_owned(), value);
                }
                Ok(payload)
            })
            .await
            .map_err(|e| e.to_string())?;
        let written = path.to_string_lossy().into_owned();
        self.runtime
            .spawn_blocking(move || -> Result<(), String> {
                let json =
                    backup::encrypt_payload(&payload, &passphrase).map_err(|e| e.to_string())?;
                if let Some(parent) = path
                    .parent()
                    .filter(|parent| !parent.as_os_str().is_empty())
                {
                    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
                }
                // A failed write never truncates a previous good backup.
                let temp = path.with_extension(format!("{}.partial", uuid::Uuid::new_v4()));
                let result = (|| {
                    std::fs::write(&temp, json)?;
                    std::fs::File::open(&temp)?.sync_all()?;
                    std::fs::rename(&temp, &path)
                })();
                if result.is_err() {
                    let _ = std::fs::remove_file(&temp);
                }
                result.map_err(|e| e.to_string())
            })
            .await
            .map_err(|e| e.to_string())??;
        Ok(written)
    }

    /// Backups kept inside this installation, newest name first.
    pub async fn local_backups(&self) -> Result<Vec<PathBuf>, String> {
        let Some(dir) = self.app_dir.as_ref().map(|dir| dir.join("backups")) else {
            return Ok(Vec::new());
        };
        self.runtime
            .spawn_blocking(move || {
                if !dir.exists() {
                    return Ok(Vec::new());
                }
                let mut paths = std::fs::read_dir(dir)
                    .map_err(|e| e.to_string())?
                    .filter_map(|entry| entry.ok().map(|entry| entry.path()))
                    .filter(|path| {
                        path.is_file() && path.extension().is_some_and(|ext| ext == "bak")
                    })
                    .collect::<Vec<_>>();
                paths.sort_by(|a, b| b.file_name().cmp(&a.file_name()));
                Ok(paths)
            })
            .await
            .map_err(|e| e.to_string())?
    }

    pub async fn backup_import(
        &self,
        path: PathBuf,
        passphrase: String,
    ) -> Result<RestoreReport, String> {
        let mut payload = self
            .runtime
            .spawn_blocking(move || {
                if std::fs::metadata(&path).map_err(|e| e.to_string())?.len() > 128 * 1024 * 1024 {
                    return Err("请选择不超过 128 MB 的备份文件".to_owned());
                }
                let json = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
                backup::decrypt_payload(&json, &passphrase).map_err(|e| e.to_string())
            })
            .await
            .map_err(|e| e.to_string())??;
        let registry = self.full_registry();
        let expected: BTreeSet<_> = registry
            .adapters()
            .iter()
            .map(|adapter| adapter.table().to_owned())
            .collect();
        if payload.domain.is_some()
            || payload.tables.keys().cloned().collect::<BTreeSet<_>>() != expected
        {
            return Err("请选择此客户端导出的完整备份文件".to_owned());
        }
        let owners: BTreeSet<String> = payload
            .data
            .values()
            .flatten()
            .filter_map(|row| {
                row.get("owner_user_id")
                    .and_then(|v| v.as_str())
                    .map(str::to_owned)
            })
            .collect();
        if owners.len() > 1 {
            return Err("备份包含多个数据空间，无法安全恢复".to_owned());
        }
        let current_owner = self.owner();
        let backup_owner = owners
            .into_iter()
            .next()
            .unwrap_or_else(|| current_owner.clone());
        if current_owner != LOCAL_OWNER
            && backup_owner != LOCAL_OWNER
            && current_owner != backup_owner
        {
            return Err("此备份属于另一账户，当前数据未更改".to_owned());
        }
        let target_owner = if current_owner == LOCAL_OWNER {
            backup_owner.clone()
        } else {
            current_owner.clone()
        };
        if backup_owner != target_owner {
            remap_backup_owner(&mut payload, &backup_owner, &target_owner)
                .map_err(|e| e.to_string())?;
        }
        // Early v2 snapshots omitted disabled switches. Missing preferences must
        // restore their default instead of retaining the device's later state.
        for key in backup_preference_keys() {
            payload
                .preferences
                .entry(key.to_owned())
                .or_insert_with(|| {
                    if key == settings_repository::BASE_CURRENCY_KEY {
                        "CNY"
                    } else {
                        "0"
                    }
                    .to_owned()
                });
        }
        for (key, value) in &payload.preferences {
            if backup_preference_keys().contains(&key.as_str()) {
                if key == settings_repository::BASE_CURRENCY_KEY {
                    Currency::new(value).map_err(|e| e.to_string())?;
                } else if value != "0" && value != "1" {
                    return Err("备份中的领域设置无效".to_owned());
                }
            }
        }
        let device_id = self.device_id.clone();
        let owner = target_owner.clone();
        let report = self
            .db
            .call(move |conn| {
                in_savepoint(conn, |conn| {
                    let report = backup::restore_payload(&registry, conn, &payload)?;
                    for (key, value) in &payload.preferences {
                        if backup_preference_keys().contains(&key.as_str()) {
                            settings::set_setting(conn, key, value)?;
                        }
                    }
                    if current_owner != owner {
                        for key in ["sync.access_token", "sync.user_id", "sync.expires_at"] {
                            settings::delete_setting(conn, key)?;
                        }
                    }
                    ensure_identity(conn, &owner, &device_id)?;
                    naviwealth_finance::wealth::rebuild_manual_fx(conn, &owner)?;
                    settings::set_setting(conn, "sync.cursor", "0")?;
                    Ok(report)
                })
            })
            .await
            .map_err(|e| e.to_string())?;
        *self.owner.write().unwrap() = target_owner;
        let enabled = self
            .db
            .call(|conn| {
                let mut enabled = BTreeSet::new();
                for spec in domains::OPTIONAL_DOMAINS {
                    if settings::get_setting(conn, spec.enabled_key)?.as_deref() == Some("1") {
                        enabled.insert(spec.key);
                    }
                }
                Ok(enabled)
            })
            .await
            .map_err(|e| e.to_string())?;
        *self.enabled_domains.write().unwrap() = enabled;
        Ok(report)
    }

    // ---- Domain lookups for the AI write tools ----

    /// The user-facing expense category for a preset key (`dining`):
    /// (ledger account id, display name).
    pub async fn expense_category_by_key(
        &self,
        key: &str,
    ) -> Result<Option<(String, String)>, String> {
        let key = key.to_owned();
        self.db
            .call(move |conn| {
                let mut stmt = conn.prepare_cached(
                    r#"SELECT c.ledger_account_id, c.name, c.name_override FROM "fin:categories" c
                     WHERE c.system_key = ?1 AND c.deleted_at IS NULL AND c.archived = 0"#,
                )?;
                use rusqlite::OptionalExtension as _;
                let row = stmt
                    .query_row(rusqlite::params![key], |row| {
                        Ok((
                            row.get::<_, String>(0)?,
                            row.get::<_, String>(1)?,
                            row.get::<_, Option<String>>(2)?,
                        ))
                    })
                    .optional()?;
                Ok(row.map(|(id, name, override_name)| {
                    let display = naviwealth_finance::system_accounts::category_display_name(
                        name.as_str(),
                        override_name.as_deref(),
                        true,
                    );
                    (id, display.to_owned())
                }))
            })
            .await
            .map_err(|e| e.to_string())
    }

    /// Resolve an account by id first, then by exact name (active accounts
    /// only). Used by the AI write tool (`from_account_id 或账户名`).
    pub async fn account_by_id_or_name(&self, value: &str) -> Result<Option<Account>, String> {
        let value = value.trim().to_owned();
        if value.is_empty() {
            return Ok(None);
        }
        self.db
            .call(move |conn| {
                let accounts =
                    account_repository::list(conn, false).map_err(lifeos::LifeosError::from)?;
                Ok(accounts
                    .into_iter()
                    .find(|a| a.id == value || a.name == value))
            })
            .await
            .map_err(|e| e.to_string())
    }

    /// Resolve a plan by id, exact title, then unique title prefix.
    pub async fn plan_by_id_or_title(
        &self,
        value: &str,
    ) -> Result<Option<naviwealth_execution::models::Plan>, String> {
        let value = value.trim().to_owned();
        if value.is_empty() {
            return Ok(None);
        }
        self.db
            .call(move |conn| {
                let plans = naviwealth_execution::repos::plan_repository::list(conn)
                    .map_err(lifeos::LifeosError::from)?;
                Ok(plans
                    .iter()
                    .find(|p| p.id == value)
                    .or_else(|| plans.iter().find(|p| p.title == value))
                    .or_else(|| {
                        let hits: Vec<_> = plans
                            .iter()
                            .filter(|p| p.title.starts_with(&value))
                            .collect();
                        (hits.len() == 1).then(|| hits[0])
                    })
                    .cloned())
            })
            .await
            .map_err(|e| e.to_string())
    }

    // ---- Knowledge reads/writes ----

    pub async fn notes(
        &self,
        limit: i64,
    ) -> Result<Vec<naviwealth_knowledge::models::Note>, String> {
        self.db
            .call(move |conn| {
                naviwealth_knowledge::repos::note_repository::list_recent(conn, limit)
                    .map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn create_note(
        &self,
        title: String,
        content: String,
        source: Option<String>,
    ) -> Result<naviwealth_knowledge::models::Note, String> {
        let stamper = self.stamper();
        self.db
            .call(move |conn| {
                let new = naviwealth_knowledge::models::NewNote {
                    title,
                    content,
                    source,
                    created_at: lifeos::ids::now_secs(),
                };
                naviwealth_knowledge::repos::note_repository::create(conn, &stamper, new)
                    .map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn decisions(
        &self,
        limit: i64,
    ) -> Result<Vec<naviwealth_knowledge::models::Decision>, String> {
        self.db
            .call(move |conn| {
                naviwealth_knowledge::repos::decision_repository::list_recent(conn, limit)
                    .map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    // ---- Execution reads/writes ----

    /// Every plan with its non-deleted actions, open plans first.
    pub async fn plans_with_actions(
        &self,
    ) -> Result<
        Vec<(
            naviwealth_execution::models::Plan,
            Vec<naviwealth_execution::models::Action>,
        )>,
        String,
    > {
        self.db
            .call(|conn| {
                let plans = naviwealth_execution::repos::plan_repository::list(conn)
                    .map_err(lifeos::LifeosError::from)?;
                let mut out = Vec::with_capacity(plans.len());
                for plan in plans {
                    let actions = naviwealth_execution::repos::action_repository::list_by_plan(
                        conn, &plan.id,
                    )
                    .map_err(lifeos::LifeosError::from)?;
                    out.push((plan, actions));
                }
                Ok(out)
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn create_plan(
        &self,
        title: String,
        kind: naviwealth_execution::models::PlanKind,
        period: naviwealth_execution::models::PlanPeriod,
    ) -> Result<naviwealth_execution::models::Plan, String> {
        let stamper = self.stamper();
        self.db
            .call(move |conn| {
                let new = naviwealth_execution::models::NewPlan {
                    title,
                    kind,
                    period,
                    status: naviwealth_execution::models::PlanStatus::Active,
                    created_at: lifeos::ids::now_secs(),
                };
                naviwealth_execution::repos::plan_repository::create(conn, &stamper, new)
                    .map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn create_action(
        &self,
        plan_id: String,
        title: String,
        due: Option<i64>,
    ) -> Result<naviwealth_execution::models::Action, String> {
        let stamper = self.stamper();
        self.db
            .call(move |conn| {
                let new = naviwealth_execution::models::NewAction {
                    plan_id,
                    title,
                    due,
                    created_at: lifeos::ids::now_secs(),
                };
                naviwealth_execution::repos::action_repository::create(conn, &stamper, new)
                    .map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    /// Flip an action's status (the progress record): `done` completes it,
    /// `todo` reopens it.
    pub async fn set_action_status(
        &self,
        action_id: String,
        status: naviwealth_execution::models::ActionStatus,
    ) -> Result<(), String> {
        let stamper = self.stamper();
        self.db
            .call(move |conn| {
                naviwealth_execution::repos::action_repository::set_status(
                    conn, &stamper, &action_id, status,
                )
                .map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    // ---- Health reads/writes ----

    pub async fn recent_metrics(
        &self,
        limit: i64,
    ) -> Result<Vec<naviwealth_health::models::Metric>, String> {
        self.db
            .call(move |conn| {
                naviwealth_health::repos::metric_repository::list_recent(conn, limit)
                    .map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn record_metric(
        &self,
        kind: naviwealth_health::models::MetricKind,
        quantity: Decimal,
    ) -> Result<naviwealth_health::models::Metric, String> {
        let stamper = self.stamper();
        self.db
            .call(move |conn| {
                let new = naviwealth_health::models::NewMetric::now(kind, quantity);
                naviwealth_health::repos::metric_repository::create(conn, &stamper, new)
                    .map_err(lifeos::LifeosError::from)
            })
            .await
            .map_err(|e| e.to_string())
    }

    // ---- Finance AI tool reads ----

    /// Account balances as (name, "100.00 CNY") display strings.
    pub async fn account_balance_lines(&self) -> Result<Vec<String>, String> {
        self.db
            .call(|conn| {
                let accounts =
                    account_repository::list(conn, false).map_err(lifeos::LifeosError::from)?;
                let balances = account_repository::balances(conn)?;
                Ok(accounts
                    .into_iter()
                    .filter_map(|account| {
                        let balance = balances.iter().find(|b| b.account_id == account.id)?;
                        let legs = balance
                            .legs
                            .iter()
                            .map(|(unit, amount)| format!("{amount} {unit}"))
                            .collect::<Vec<_>>()
                            .join("、");
                        Some(format!("{}：{}", account.name, legs))
                    })
                    .collect())
            })
            .await
            .map_err(|e| e.to_string())
    }

    /// Recent entries as human-readable summary lines (account names
    /// resolved in the same DB pass).
    pub async fn recent_entry_lines(&self, limit: i64) -> Result<Vec<String>, String> {
        self.db
            .call(move |conn| {
                let entries = journal_repository::list_recent(conn, limit)
                    .map_err(lifeos::LifeosError::from)?;
                let accounts =
                    account_repository::list(conn, true).map_err(lifeos::LifeosError::from)?;
                let name = |id: &str| {
                    accounts
                        .iter()
                        .find(|a| a.id == id)
                        .map(|a| a.name.clone())
                        .unwrap_or_else(|| id.to_owned())
                };
                Ok(entries
                    .into_iter()
                    .map(|with| {
                        let legs = with
                            .postings
                            .iter()
                            .map(|p| format!("{} {} {}", name(&p.account_id), p.units, p.unit))
                            .collect::<Vec<_>>()
                            .join("；");
                        format!("{}：{}", with.entry.narration, legs)
                    })
                    .collect())
            })
            .await
            .map_err(|e| e.to_string())
    }

    // ---- Knowledge / Execution / Health AI tool reads ----

    /// Notes whose title or content contains the keyword (case-insensitive),
    /// as `《title》content` lines.
    pub async fn note_search_lines(&self, query: &str, limit: i64) -> Result<Vec<String>, String> {
        let needle = query.trim().to_lowercase();
        self.db
            .call(move |conn| {
                let notes = naviwealth_knowledge::repos::note_repository::list_recent(conn, 500)
                    .map_err(lifeos::LifeosError::from)?;
                Ok(notes
                    .into_iter()
                    .filter(|note| {
                        let haystack = format!("{} {}", note.title, note.content).to_lowercase();
                        haystack.contains(&needle)
                    })
                    .take(limit.max(1) as usize)
                    .map(|note| {
                        let content: String = note.content.chars().take(80).collect();
                        format!("《{}》{}", note.title, content)
                    })
                    .collect())
            })
            .await
            .map_err(|e| e.to_string())
    }

    /// Per-plan open (non-deleted, non-done) actions as display lines.
    pub async fn open_action_lines(&self) -> Result<Vec<String>, String> {
        use naviwealth_execution::models::ActionStatus;
        self.db
            .call(|conn| {
                let plans = naviwealth_execution::repos::plan_repository::list(conn)
                    .map_err(lifeos::LifeosError::from)?;
                let mut out = Vec::new();
                for plan in plans {
                    let actions = naviwealth_execution::repos::action_repository::list_by_plan(
                        conn, &plan.id,
                    )
                    .map_err(lifeos::LifeosError::from)?;
                    let open: Vec<String> = actions
                        .into_iter()
                        .filter(|a| {
                            a.status != ActionStatus::Done && a.status != ActionStatus::Dropped
                        })
                        .map(|a| match a.status {
                            ActionStatus::Doing => format!("{}（进行中）", a.title),
                            ActionStatus::Blocked => format!("{}（受阻）", a.title),
                            _ => a.title,
                        })
                        .collect();
                    if open.is_empty() {
                        continue;
                    }
                    out.push(format!("《{}》：{}", plan.title, open.join("；")));
                }
                Ok(out)
            })
            .await
            .map_err(|e| e.to_string())
    }

    /// Recent metrics as `步数 8000 count（2026-01-01）` lines, optionally
    /// filtered by kind.
    pub async fn recent_metric_lines(
        &self,
        limit: i64,
        kind: Option<naviwealth_health::models::MetricKind>,
    ) -> Result<Vec<String>, String> {
        self.db
            .call(move |conn| {
                let metrics = match kind {
                    Some(kind) => {
                        naviwealth_health::repos::metric_repository::list_by_kind(conn, kind, limit)
                            .map_err(lifeos::LifeosError::from)?
                    }
                    None => naviwealth_health::repos::metric_repository::list_recent(conn, limit)
                        .map_err(lifeos::LifeosError::from)?,
                };
                Ok(metrics
                    .into_iter()
                    .map(|m| {
                        format!(
                            "{} {} {}（{}）",
                            metric_kind_label(m.kind),
                            m.quantity,
                            m.unit,
                            crate::ui::ymd(m.recorded_at)
                        )
                    })
                    .collect())
            })
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

/// Keep multi-repository mutations atomic, including APIs creating nested savepoints.
fn in_savepoint<T>(
    conn: &mut rusqlite::Connection,
    work: impl FnOnce(&mut rusqlite::Connection) -> LifeosResult<T>,
) -> LifeosResult<T> {
    conn.execute_batch("SAVEPOINT naviwealth_app_operation")?;
    match work(conn) {
        Ok(value) => {
            if let Err(error) = conn.execute_batch("RELEASE naviwealth_app_operation") {
                let _ = conn.execute_batch(
                    "ROLLBACK TO naviwealth_app_operation; RELEASE naviwealth_app_operation",
                );
                return Err(error.into());
            }
            Ok(value)
        }
        Err(error) => {
            conn.execute_batch(
                "ROLLBACK TO naviwealth_app_operation; RELEASE naviwealth_app_operation",
            )?;
            Err(error)
        }
    }
}

fn backup_preference_keys() -> Vec<&'static str> {
    std::iter::once(settings_repository::BASE_CURRENCY_KEY)
        .chain(
            domains::OPTIONAL_DOMAINS
                .iter()
                .map(|spec| spec.enabled_key),
        )
        .collect()
}

fn remap_backup_owner(
    payload: &mut backup::BackupPayload,
    previous: &str,
    owner: &str,
) -> LifeosResult<()> {
    fn remap_id(id: &str, previous: &str, owner: &str) -> String {
        for prefix in ["system-account", "system-category"] {
            if let Some(rest) = id.strip_prefix(&format!("{prefix}:{previous}:")) {
                return format!("{prefix}:{owner}:{rest}");
            }
        }
        let (prefix, json) = if let Some(json) = id.strip_prefix("planning:") {
            ("planning:", json)
        } else {
            ("", id)
        };
        if let Ok(mut parts) = serde_json::from_str::<Vec<String>>(json)
            && parts.first().is_some_and(|v| v == previous)
            && parts.get(1).is_some_and(|v| {
                matches!(
                    v.as_str(),
                    "budget"
                        | "recurring-occurrence"
                        | "installment"
                        | "dca-occurrence"
                        | "contribution"
                        | "rebalance"
                )
            })
        {
            parts[0] = owner.into();
            for part in parts.iter_mut().skip(2) {
                *part = remap_id(part, previous, owner);
            }
            return format!(
                "{prefix}{}",
                serde_json::to_string(&parts).expect("string list")
            );
        }
        id.into()
    }
    fn remap(value: &mut serde_json::Value, field: &str, previous: &str, owner: &str) {
        match value {
            serde_json::Value::Object(object) => {
                for (key, value) in object {
                    remap(value, key, previous, owner);
                }
            }
            serde_json::Value::Array(values) => {
                for value in values {
                    remap(value, field, previous, owner);
                }
            }
            serde_json::Value::String(text) if field == "payload" || field == "payload_json" => {
                if let Ok(mut nested) = serde_json::from_str::<serde_json::Value>(text) {
                    remap(&mut nested, "", previous, owner);
                    *text = nested.to_string();
                }
            }
            serde_json::Value::String(text) if field == "owner_user_id" => *text = owner.into(),
            serde_json::Value::String(text)
                if field == "id" || field.ends_with("_id") || field.ends_with("_ids") =>
            {
                *text = remap_id(text, previous, owner)
            }
            _ => {}
        }
    }
    for rows in payload.data.values_mut() {
        for row in rows {
            remap(row, "", previous, owner);
        }
    }
    if let Some(rows) = payload.data.get_mut("fin:operations") {
        for row in rows {
            naviwealth_finance::operations::remap_owner_row(row, previous, owner)?;
        }
    }
    Ok(())
}

/// Move only evidence which still matches its recorded journal revision. A stale
/// receipt must remain stale after adoption; re-stamping must not validate it.
fn restamp_backup_evidence(
    payload: &mut backup::BackupPayload,
    revisions: &std::collections::BTreeMap<String, (String, i64)>,
) {
    let journals = payload
        .data
        .get("fin:journal_entries")
        .into_iter()
        .flatten()
        .filter_map(|row| {
            Some((
                row.get("id")?.as_str()?.to_owned(),
                row.get("hlc")?.as_str()?.to_owned(),
            ))
        })
        .collect::<std::collections::BTreeMap<_, _>>();
    fn update(
        value: &mut serde_json::Value,
        journals: &std::collections::BTreeMap<String, String>,
        revisions: &std::collections::BTreeMap<String, (String, i64)>,
    ) {
        match value {
            serde_json::Value::Object(object) => {
                let new_hlc = object
                    .get("journal_id")
                    .and_then(|v| v.as_str())
                    .and_then(|id| journals.get(id))
                    .filter(|old| {
                        object.get("journal_hlc").and_then(|v| v.as_str()) == Some(old.as_str())
                    })
                    .and_then(|old| revisions.get(old))
                    .map(|(hlc, _)| hlc.clone());
                if let Some(new_hlc) = new_hlc {
                    object.insert("journal_hlc".into(), serde_json::Value::String(new_hlc));
                }
                for (key, value) in object {
                    if (key == "payload" || key == "payload_json") && value.is_string() {
                        if let Ok(mut nested) = serde_json::from_str::<serde_json::Value>(
                            value.as_str().unwrap_or_default(),
                        ) {
                            update(&mut nested, journals, revisions);
                            *value = serde_json::Value::String(nested.to_string());
                        }
                    } else {
                        update(value, journals, revisions);
                    }
                }
            }
            serde_json::Value::Array(values) => {
                for value in values {
                    update(value, journals, revisions);
                }
            }
            _ => {}
        }
    }
    for rows in payload.data.values_mut() {
        for row in rows {
            update(row, &journals, revisions);
        }
    }
}

/// First sign-in adopts offline records and their references in one savepoint.
fn adopt_local_owner(
    conn: &rusqlite::Connection,
    registry: &SyncRegistry,
    previous: &str,
    owner: &str,
    device: &str,
) -> LifeosResult<()> {
    if previous == owner {
        return Ok(());
    }
    if previous != LOCAL_OWNER {
        return Err(lifeos::LifeosError::Auth(
            "当前设备已有另一账户的数据，请先备份后使用独立数据空间".to_owned(),
        ));
    }
    let mut payload =
        backup::export_payload(registry, conn, None, chrono::Utc::now().to_rfc3339())?;
    if payload.data.values().flatten().any(|row| {
        row.get("owner_user_id")
            .and_then(|value| value.as_str())
            .is_some_and(|value| value != previous)
    }) {
        return Err(lifeos::LifeosError::Auth(
            "本地包含多个数据空间，请先备份".to_owned(),
        ));
    }
    remap_backup_owner(&mut payload, previous, owner)?;
    // Preserve revision equivalence: a partially received edit must remain
    // incomplete after sign-in, while each complete journal and its postings
    // continue to share a revision. Fresh stamps still publish the adopted rows.
    let original = payload
        .data
        .values()
        .flatten()
        .filter_map(|row| row.get("hlc").and_then(|v| v.as_str()).map(str::to_owned))
        .collect::<BTreeSet<_>>();
    let stamper = MutationStamper::new(owner, device);
    let mut revisions = std::collections::BTreeMap::new();
    for old in original {
        let stamp = stamper.stamp(conn)?;
        revisions.insert(old, (stamp.hlc, stamp.now.div_euclid(1000)));
    }
    restamp_backup_evidence(&mut payload, &revisions);
    for adapter in registry.adapters() {
        adapter.delete_all(conn)?;
        outbox::clear_table(conn, adapter.table())?;
        if let Some(rows) = payload.data.get_mut(adapter.table()) {
            for row in rows {
                let object = row.as_object_mut().ok_or_else(|| {
                    lifeos::LifeosError::InvalidData("backup row must be an object".into())
                })?;
                let (hlc, updated_at) = object
                    .get("hlc")
                    .and_then(|v| v.as_str())
                    .and_then(|old| revisions.get(old))
                    .ok_or_else(|| {
                        lifeos::LifeosError::InvalidData("adoption row revision is missing".into())
                    })?
                    .clone();
                object.insert("hlc".into(), serde_json::Value::String(hlc));
                object.insert(
                    "updated_by_device".into(),
                    serde_json::Value::String(device.to_owned()),
                );
                object.insert("updated_at".into(), serde_json::json!(updated_at));
                adapter.apply_upsert(conn, row)?;
                if let Some(id) = row.get("id").and_then(|id| id.as_str()) {
                    outbox::enqueue(conn, adapter.table(), id)?;
                }
            }
        }
    }
    settings::set_setting(conn, "sync.cursor", "0")?;
    Ok(())
}

/// Chinese display label for a health metric kind (matches the health
/// screen's wording).
fn metric_kind_label(kind: naviwealth_health::models::MetricKind) -> &'static str {
    match kind {
        naviwealth_health::models::MetricKind::Steps => "步数",
        naviwealth_health::models::MetricKind::Sleep => "睡眠",
        naviwealth_health::models::MetricKind::Weight => "体重",
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

#[cfg(test)]
#[path = "state_finance_tests.rs"]
mod finance_recovery_tests;

#[cfg(test)]
mod startup_tests {
    use super::*;

    fn temp_dir() -> PathBuf {
        std::env::temp_dir().join(format!("naviwealth-startup-{}", uuid::Uuid::new_v4()))
    }

    #[test]
    fn encrypted_startup_reopens_with_same_key_and_identity() {
        let dir = temp_dir();
        let first = Services::init_at(Some(dir.clone())).unwrap();
        assert!(first.encrypted);
        assert!(dir.join("naviwealth.db").is_file());
        // Verify SQLCipher actually encrypted the file, rather than trusting
        // the service's flag or silently opening a plaintext SQLite database.
        let without_key = rusqlite::Connection::open(dir.join("naviwealth.db")).unwrap();
        assert!(
            without_key
                .query_row("SELECT count(*) FROM sqlite_master", [], |row| row
                    .get::<_, i64>(0))
                .is_err()
        );
        drop(without_key);
        let device_id = first.device_id.clone();
        drop(first);
        let reopened = Services::init_at(Some(dir)).unwrap();
        assert!(reopened.encrypted);
        assert_eq!(reopened.device_id, device_id);
    }

    #[test]
    fn account_and_opening_balance_roll_back_together() {
        let services = Services::init_at(None).unwrap();
        services
            .db
            .call_sync(|conn| {
                conn.execute(
                    r#"DELETE FROM "fin:accounts" WHERE id=?1"#,
                    [account_repository::system_account_id(
                        LOCAL_OWNER,
                        "equity:openingBalance",
                    )],
                )?;
                Ok(())
            })
            .unwrap();
        let before = services.db.call_sync(|conn| outbox::count(conn)).unwrap();
        let result = services.runtime.block_on(services.create_account(
            NewAccount::custody(
                naviwealth_finance::models::AccountCategory::Cash,
                "Must roll back",
                "CNY",
            ),
            Some(Decimal::from(100)),
        ));
        assert!(result.is_err());
        services
            .db
            .call_sync(move |conn| {
                assert!(
                    !account_repository::list(conn, true)?
                        .iter()
                        .any(|account| account.name == "Must roll back")
                );
                assert_eq!(outbox::count(conn)?, before);
                Ok(())
            })
            .unwrap();
    }

    #[test]
    fn backup_creates_parent_and_bad_password_preserves_current_records() {
        let mut services = Services::init_at(None).unwrap();
        let directory = temp_dir();
        Arc::get_mut(&mut services).unwrap().app_dir = Some(directory.clone());
        let path = directory.join("backups").join("first.bak");
        services.runtime.block_on(async {
            services
                .create_account(
                    NewAccount::custody(
                        naviwealth_finance::models::AccountCategory::Cash,
                        "Original",
                        "CNY",
                    ),
                    Some(Decimal::from(100)),
                )
                .await
                .unwrap();
            services
                .settings_set(domains::KNOWLEDGE.enabled_key, "1")
                .await;
            services
                .backup_export(path.clone(), "passphrase".to_owned())
                .await
                .unwrap();
            assert!(path.is_file());
            assert_eq!(services.local_backups().await.unwrap(), vec![path.clone()]);
            services
                .create_account(
                    NewAccount::custody(
                        naviwealth_finance::models::AccountCategory::Bank,
                        "Later",
                        "CNY",
                    ),
                    None,
                )
                .await
                .unwrap();
            assert!(
                services
                    .backup_import(path.clone(), "wrong".to_owned())
                    .await
                    .is_err()
            );
            assert!(
                services
                    .account_names()
                    .await
                    .unwrap()
                    .iter()
                    .any(|(_, name)| name == "Later")
            );
            services
                .settings_set(domains::KNOWLEDGE.enabled_key, "0")
                .await;
            services
                .backup_import(path, "passphrase".to_owned())
                .await
                .unwrap();
            assert!(
                !services
                    .account_names()
                    .await
                    .unwrap()
                    .iter()
                    .any(|(_, name)| name == "Later")
            );
            assert!(
                services
                    .account_names()
                    .await
                    .unwrap()
                    .iter()
                    .any(|(_, name)| name == "Original")
            );
            assert!(services.domain_enabled("knowledge"));
        });
    }

    #[test]
    fn first_sign_in_keeps_local_records_and_rejects_identity_mismatch() {
        let services = Services::init_at(None).unwrap();
        services.runtime.block_on(async {
            let account = services
                .create_account(
                    NewAccount::custody(
                        naviwealth_finance::models::AccountCategory::Cash,
                        "Offline cash",
                        "CNY",
                    ),
                    Some(Decimal::from(100)),
                )
                .await
                .unwrap();
            let session = |device_id: String, owner: &str| AuthSession {
                access_token: "token".to_owned(),
                token_type: "Bearer".to_owned(),
                expires_at: lifeos::ids::now_secs() + 3600,
                user_id: owner.to_owned(),
                device_id,
            };
            assert!(
                services
                    .store_session(
                        session("wrong-device".to_owned(), "owner"),
                        "https://example.com"
                    )
                    .await
                    .is_err()
            );
            assert_eq!(services.owner(), LOCAL_OWNER);
            assert!(services.settings_get("sync.access_token").await.is_none());
            services
                .store_session(
                    session(services.device_id.clone(), "owner"),
                    "https://example.com/",
                )
                .await
                .unwrap();
            assert_eq!(services.owner(), "owner");
            assert_eq!(services.base_url().await, "https://example.com");
            services
                .db
                .call_sync(move |conn| {
                    let account = account_repository::get_required(conn, &account.id)?;
                    assert_eq!(account.sync.owner_user_id, "owner");
                    let rows = journal_repository::list_recent(conn, 10)?;
                    assert_eq!(rows.len(), 1);
                    assert_eq!(rows[0].entry.sync.owner_user_id, "owner");
                    assert!(
                        rows[0]
                            .postings
                            .iter()
                            .all(|posting| posting.sync.owner_user_id == "owner")
                    );
                    assert!(rows[0].postings.iter().any(|posting| posting.account_id
                        == account_repository::system_account_id(
                            "owner",
                            "equity:openingBalance"
                        )));
                    Ok(())
                })
                .unwrap();
            assert!(
                services
                    .store_session(
                        session(services.device_id.clone(), "another-owner"),
                        "https://example.com"
                    )
                    .await
                    .is_err()
            );
            assert_eq!(services.owner(), "owner");
        });
    }

    #[test]
    fn directory_failure_returns_error_and_can_retry() {
        let dir = temp_dir();
        std::fs::write(&dir, b"blocked").unwrap();
        assert!(matches!(
            Services::init_at(Some(dir.clone())),
            Err(lifeos::LifeosError::Io(_))
        ));
        std::fs::remove_file(&dir).unwrap();
        assert!(Services::init_at(Some(dir)).is_ok());
    }
    #[test]
    fn disabled_domain_preferences_survive_backup_and_missing_early_v2_keys() {
        let dir = temp_dir();
        let services = Services::init_at(Some(dir.clone())).unwrap();
        services.runtime.block_on(async {
            let path = dir.join("backups/defaults.bak");
            services
                .backup_export(path.clone(), "test passphrase".to_owned())
                .await
                .unwrap();
            let json = std::fs::read_to_string(&path).unwrap();
            let mut payload = backup::decrypt_payload(&json, "test passphrase").unwrap();
            for spec in domains::OPTIONAL_DOMAINS {
                assert_eq!(
                    payload
                        .preferences
                        .get(spec.enabled_key)
                        .map(String::as_str),
                    Some("0")
                );
            }
            payload.preferences.clear();
            std::fs::write(
                &path,
                backup::encrypt_payload(&payload, "test passphrase").unwrap(),
            )
            .unwrap();
            services
                .settings_set(domains::KNOWLEDGE.enabled_key, "1")
                .await;
            services.set_domain_enabled("knowledge", true);
            services
                .backup_import(path, "test passphrase".to_owned())
                .await
                .unwrap();
            assert!(!services.domain_enabled("knowledge"));
            assert_eq!(
                services
                    .settings_get(domains::KNOWLEDGE.enabled_key)
                    .await
                    .as_deref(),
                Some("0")
            );
        });
    }
}
