//! Encrypted backup and restore (format v2 — this client's own format,
//! no legacy compatibility).
//!
//! Envelope: JSON with an Argon2id KDF record and a ChaCha20-Poly1305
//! ciphertext. The payload is a table→rows snapshot over the registered
//! sync tables. Restore validates strictly, then replaces the declared
//! tables in one transaction and re-enqueues every row for sync.

use std::collections::BTreeMap;

use chacha20poly1305::aead::rand_core::RngCore;
use chacha20poly1305::aead::{Aead, KeyInit, OsRng};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

use crate::error::{LifeosError, Result};

use super::sync::outbox;
use super::sync::registry::SyncRegistry;
use super::sync::stamp::HLC_KEY;

pub const BACKUP_MAGIC: &str = "naviwealth.bak.v2";
pub const BACKUP_PAYLOAD_MAGIC: &str = "naviwealth.backup.v2";
pub const BACKUP_SCHEMA_VERSION: i64 = 1;
pub const DATABASE_KEY_ID: &str = "naviwealth.database.master_key.v2";

/// Argon2id parameters (memory in KiB, iterations, lanes).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KdfParams {
    pub alg: String,
    pub m_cost_kib: u32,
    pub t_cost: u32,
    pub p_cost: u32,
    /// Base64 salt.
    pub salt: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CipherParams {
    pub alg: String,
    /// Base64 nonce (12 bytes for ChaCha20-Poly1305).
    pub nonce: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupEnvelope {
    pub magic: String,
    pub created_at: String,
    pub schema_version: i64,
    pub kdf: KdfParams,
    pub cipher: CipherParams,
    /// Base64 ciphertext (includes the 16-byte Poly1305 tag).
    pub ciphertext: String,
}

/// The decrypted payload: full-row JSON per registered table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupPayload {
    pub magic: String,
    pub created_at: String,
    /// `None` for a full backup; a domain string for a partial one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub domain: Option<String>,
    /// Declared table → declared row count (validated against `data`).
    pub tables: BTreeMap<String, usize>,
    pub data: BTreeMap<String, Vec<serde_json::Value>>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RestoreReport {
    pub tables: usize,
    pub rows: usize,
    /// Highest HLC found in the restored rows; the local clock must not
    /// run behind it.
    pub max_hlc: Option<String>,
}

const B64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

fn b64_encode(bytes: &[u8]) -> String {
    use base64::Engine as _;
    B64.encode(bytes)
}

fn b64_decode(text: &str) -> Result<Vec<u8>> {
    use base64::Engine as _;
    B64.decode(text.trim())
        .map_err(|e| LifeosError::Backup(format!("bad base64: {e}")))
}

fn derive_key(passphrase: &str, params: &KdfParams) -> Result<[u8; 32]> {
    if params.alg != "argon2id" {
        return Err(LifeosError::Backup(format!(
            "unsupported kdf: {}",
            params.alg
        )));
    }
    let salt = b64_decode(&params.salt)?;
    let mut key = [0u8; 32];
    argon2::Argon2::new(
        argon2::Algorithm::Argon2id,
        argon2::Version::V0x13,
        argon2::Params::new(params.m_cost_kib, params.t_cost, params.p_cost, Some(32))
            .map_err(|e| LifeosError::Backup(format!("bad kdf params: {e}")))?,
    )
    .hash_password_into(passphrase.as_bytes(), &salt, &mut key)
    .map_err(|e| LifeosError::Backup(format!("kdf failed: {e}")))?;
    Ok(key)
}

/// Encrypt a payload into the v2 envelope JSON.
pub fn encrypt_payload(payload: &BackupPayload, passphrase: &str) -> Result<String> {
    if passphrase.is_empty() {
        return Err(LifeosError::Backup("passphrase must not be empty".into()));
    }
    let mut salt = [0u8; 16];
    OsRng.fill_bytes(&mut salt);
    let kdf = KdfParams {
        alg: "argon2id".into(),
        m_cost_kib: 19456,
        t_cost: 2,
        p_cost: 1,
        salt: b64_encode(&salt),
    };
    let key = derive_key(passphrase, &kdf)?;

    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
    let plaintext = serde_json::to_vec(payload)?;
    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce_bytes), plaintext.as_ref())
        .map_err(|_| LifeosError::Backup("encryption failed".into()))?;

    let envelope = BackupEnvelope {
        magic: BACKUP_MAGIC.into(),
        created_at: chrono::Utc::now().to_rfc3339(),
        schema_version: BACKUP_SCHEMA_VERSION,
        kdf,
        cipher: CipherParams {
            alg: "chacha20poly1305".into(),
            nonce: b64_encode(&nonce_bytes),
        },
        ciphertext: b64_encode(&ciphertext),
    };
    serde_json::to_string_pretty(&envelope).map_err(Into::into)
}

/// Decrypt an envelope JSON back into the payload. A wrong passphrase and
/// a tampered file are deliberately indistinguishable.
pub fn decrypt_payload(envelope_json: &str, passphrase: &str) -> Result<BackupPayload> {
    let envelope: BackupEnvelope = serde_json::from_str(envelope_json)
        .map_err(|e| LifeosError::Backup(format!("bad envelope: {e}")))?;
    if envelope.magic != BACKUP_MAGIC {
        return Err(LifeosError::Backup(format!(
            "unknown backup magic: {}",
            envelope.magic
        )));
    }
    if envelope.schema_version > BACKUP_SCHEMA_VERSION {
        return Err(LifeosError::Backup(
            "backup was written by a newer schema".into(),
        ));
    }
    let key = derive_key(passphrase, &envelope.kdf)?;
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
    let nonce = b64_decode(&envelope.cipher.nonce)?;
    let ciphertext = b64_decode(&envelope.ciphertext)?;
    let plaintext = cipher
        .decrypt(Nonce::from_slice(&nonce), ciphertext.as_ref())
        .map_err(|_| {
            LifeosError::Backup("decryption failed (wrong passphrase or corrupted file)".into())
        })?;
    let payload: BackupPayload = serde_json::from_slice(&plaintext)?;
    if payload.magic != BACKUP_PAYLOAD_MAGIC {
        return Err(LifeosError::Backup(format!(
            "unknown payload magic: {}",
            payload.magic
        )));
    }
    Ok(payload)
}

/// Snapshot every registered table (optionally one domain only).
pub fn export_payload(
    registry: &SyncRegistry,
    conn: &Connection,
    domain: Option<crate::error::Domain>,
    created_at: String,
) -> Result<BackupPayload> {
    let mut tables = BTreeMap::new();
    let mut data = BTreeMap::new();
    for adapter in registry.adapters() {
        if let Some(want) = domain
            && adapter.domain() != want
        {
            continue;
        }
        let rows = adapter.read_all(conn)?;
        tables.insert(adapter.table().to_owned(), rows.len());
        data.insert(adapter.table().to_owned(), rows);
    }
    Ok(BackupPayload {
        magic: BACKUP_PAYLOAD_MAGIC.into(),
        created_at,
        domain: domain.map(|d| d.as_str().to_owned()),
        tables,
        data,
    })
}

/// Validate and restore a payload in one transaction: declared tables are
/// replaced, rows re-inserted as-is, outbox pointers re-enqueued and the
/// local HLC clock advanced past the highest restored version.
pub fn restore_payload(
    registry: &SyncRegistry,
    conn: &mut Connection,
    payload: &BackupPayload,
) -> Result<RestoreReport> {
    // ---- Validation (before touching a row) ----
    if payload.magic != BACKUP_PAYLOAD_MAGIC {
        return Err(LifeosError::Backup(format!(
            "unknown payload magic: {}",
            payload.magic
        )));
    }
    for (table, count) in &payload.tables {
        let Some(adapter) = registry.adapter(table) else {
            return Err(LifeosError::Backup(format!(
                "backup contains unknown table {table:?}"
            )));
        };
        let rows = payload
            .data
            .get(table)
            .ok_or_else(|| LifeosError::Backup(format!("table {table:?} missing from data")))?;
        if rows.len() != *count {
            return Err(LifeosError::Backup(format!(
                "table {table:?} declares {count} rows but data has {}",
                rows.len()
            )));
        }
        for (index, row) in rows.iter().enumerate() {
            if row.get("id").and_then(|v| v.as_str()).is_none() {
                return Err(LifeosError::Backup(format!(
                    "table {table:?} row {index} has no id"
                )));
            }
        }
        let _ = adapter; // table known
    }
    for table in payload.data.keys() {
        if !payload.tables.contains_key(table) {
            return Err(LifeosError::Backup(format!(
                "data table {table:?} not declared in tables"
            )));
        }
    }

    // ---- Replace ----
    let tx = conn.transaction()?;
    let mut rows_restored = 0usize;
    let mut max_hlc: Option<String> = None;
    for (table, rows) in &payload.data {
        let adapter = registry
            .adapter(table)
            .ok_or_else(|| LifeosError::Backup(format!("unknown table {table:?}")))?;
        adapter.delete_all(&tx)?;
        outbox::clear_table(&tx, table)?;
        for row in rows {
            adapter.apply_upsert(&tx, row)?;
            if let Some(id) = row.get("id").and_then(|v| v.as_str()) {
                outbox::enqueue(&tx, table, id)?;
            }
            if let Some(hlc) = row.get("hlc").and_then(|v| v.as_str())
                && max_hlc.as_deref().is_none_or(|current| hlc > current)
            {
                max_hlc = Some(hlc.to_owned());
            }
            rows_restored += 1;
        }
    }
    if let Some(hlc) = &max_hlc {
        // The local clock must never stamp below a restored version.
        let current = crate::db::settings::get_setting(&tx, HLC_KEY)?;
        let needs_update = current.as_deref().map(|c| c < hlc.as_str()).unwrap_or(true);
        if needs_update {
            crate::db::settings::set_setting(&tx, HLC_KEY, hlc)?;
        }
    }
    tx.commit()?;
    Ok(RestoreReport {
        tables: payload.tables.len(),
        rows: rows_restored,
        max_hlc,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Db;
    use crate::error::Domain;
    use crate::sync::{MutationStamper, SqlTableAdapter, SyncRegistry};
    use std::sync::Arc;

    fn registry() -> SyncRegistry {
        let mut registry = SyncRegistry::new();
        registry.add(Arc::new(SqlTableAdapter::new(
            "fin:notes",
            Domain::Finance,
            &[
                "id",
                "note",
                "owner_user_id",
                "updated_at",
                "updated_by_device",
                "hlc",
                "deleted_at",
            ],
        )));
        registry
    }

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let payload = BackupPayload {
            magic: BACKUP_PAYLOAD_MAGIC.into(),
            created_at: "2026-01-01T00:00:00Z".into(),
            domain: None,
            tables: BTreeMap::from([("fin:notes".into(), 1)]),
            data: BTreeMap::from([(
                "fin:notes".into(),
                vec![serde_json::json!({"id": "n1", "note": "hello"})],
            )]),
        };
        let envelope = encrypt_payload(&payload, "correct horse").unwrap();
        let decrypted = decrypt_payload(&envelope, "correct horse").unwrap();
        assert_eq!(decrypted.data["fin:notes"][0]["note"], "hello");
        assert!(decrypt_payload(&envelope, "wrong").is_err());
        assert!(decrypt_payload(&envelope[..envelope.len() - 2], "correct horse").is_err());
    }

    #[tokio::test]
    async fn export_restore_roundtrip_reenqueues_rows() {
        let db = Db::open_in_memory().unwrap();
        let registry = registry();

        // Seed one row; capture its HLC (the exact stamp used for the
        // insert) for the restore assertions.
        let expected_hlc = std::sync::Mutex::new(String::new());
        let expected_slot = std::sync::Arc::new(expected_hlc);
        let slot = expected_slot.clone();
        let stamper = MutationStamper::new("u1", "d1");
        db.call_sync(move |conn| {
            let stamp = stamper.stamp(conn)?;
            *slot.lock().unwrap() = stamp.hlc.clone();
            conn.execute_batch(
                r#"CREATE TABLE "fin:notes" (
                    id TEXT PRIMARY KEY NOT NULL,
                    note TEXT,
                    owner_user_id TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    updated_by_device TEXT NOT NULL,
                    hlc TEXT NOT NULL,
                    deleted_at INTEGER
                );"#,
            )?;
            conn.execute(
                r#"INSERT INTO "fin:notes" (id, note, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
                   VALUES ('n1', 'hello', 'u1', 1, 'd1', ?1, NULL)"#,
                rusqlite::params![stamp.hlc],
            )?;
            Ok(())
        })
        .unwrap();

        let payload = db
            .call_sync({
                let registry = registry.clone();
                move |conn| export_payload(&registry, conn, None, "t".into())
            })
            .unwrap();
        assert_eq!(payload.tables["fin:notes"], 1);

        let envelope = encrypt_payload(&payload, "pass").unwrap();

        let expected_hlc = Arc::clone(&expected_slot);
        let expected_hlc = expected_hlc.lock().unwrap().clone();

        // Wipe and restore into a fresh database.
        let db2 = Db::open_in_memory().unwrap();
        db2.call_sync(|conn| {
            conn.execute_batch(
                r#"CREATE TABLE "fin:notes" (
                    id TEXT PRIMARY KEY NOT NULL,
                    note TEXT,
                    owner_user_id TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    updated_by_device TEXT NOT NULL,
                    hlc TEXT NOT NULL,
                    deleted_at INTEGER
                );"#,
            )?;
            Ok(())
        })
        .unwrap();
        let decrypted = decrypt_payload(&envelope, "pass").unwrap();
        let report = db2
            .call_sync({
                let registry = registry.clone();
                let expected_hlc = expected_hlc.clone();
                move |conn| {
                    let report = restore_payload(&registry, conn, &decrypted)?;
                    assert_eq!(report.max_hlc.as_deref(), Some(expected_hlc.as_str()));
                    Ok(report)
                }
            })
            .unwrap();
        assert_eq!(report.rows, 1);
        assert_eq!(report.tables, 1);

        db2.call_sync(move |conn| {
            let count: i64 =
                conn.query_row(r#"SELECT COUNT(*) FROM "fin:notes""#, [], |r| r.get(0))?;
            assert_eq!(count, 1);
            // Outbox re-enqueued for sync.
            assert_eq!(outbox::count(conn)?, 1);
            // Clock bumped to the restored HLC.
            assert_eq!(
                crate::db::settings::get_setting(conn, HLC_KEY)?,
                Some(expected_hlc.clone())
            );
            Ok(())
        })
        .unwrap();
    }
}
