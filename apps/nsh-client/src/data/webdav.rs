//! The little of WebDAV backups need: put a file in the
//! user's folder (creating the folder once), list the backups there, get
//! one. Basic authentication; redirects are not followed with credentials.

use base64::{Engine, engine::general_purpose::STANDARD as B64};
use std::{io::Read, time::Duration};

use nsh_core::prelude::blocking;
use serde::{Deserialize, Serialize};
use url::Url;

use crate::domain::backup::EXTENSION;

/// Where backups go: a folder URL and the account. The password is kept
/// apart, under its own storage entry.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Folder {
    pub url: String,
    pub username: String,
    #[serde(skip)]
    pub password: String,
}

/// Why the server gave nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DavError {
    /// The request did not complete.
    Network,
    /// 401 / 403: the account or password is wrong.
    Unauthorized,
    /// Any other unexpected status.
    Status(u16),
}

impl Folder {
    /// The folder's URL with one trailing slash; `None` unless https (or
    /// http to this machine, for testing).
    pub fn base(&self) -> Option<String> {
        let mut url = Url::parse(self.url.trim()).ok()?;
        let local = matches!(url.host_str(), Some("127.0.0.1" | "localhost" | "[::1]"));
        if !(url.scheme() == "https" || (url.scheme() == "http" && local))
            || url.host_str().is_none()
            || !url.username().is_empty()
            || url.password().is_some()
            || url.query().is_some()
            || url.fragment().is_some()
        {
            return None;
        }
        url.set_path(&format!("{}/", url.path().trim_end_matches('/')));
        Some(url.to_string())
    }

    /// Whether it can be used.
    pub fn is_complete(&self) -> bool {
        self.base().is_some() && !self.username.trim().is_empty() && !self.password.is_empty()
    }

    fn auth(&self) -> String {
        let pair = format!("{}:{}", self.username.trim(), self.password);
        format!("Basic {}", B64.encode(pair))
    }

    async fn send(
        &self,
        method: &'static str,
        url: String,
        body: Vec<u8>,
        extra: &[(&str, &str)],
    ) -> Result<(u16, Vec<u8>), DavError> {
        let mut request = ureq::http::Request::builder()
            .method(method)
            .uri(url)
            .header("Authorization", self.auth());
        for (name, value) in extra {
            request = request.header(*name, *value);
        }
        let request = request.body(body).map_err(|_| DavError::Status(0))?;
        // Run off the engine thread. Both Android and headless NSH fetch
        // restrict extension methods; keep this adapter the same on both.
        blocking(move || {
            let agent: ureq::Agent = ureq::Agent::config_builder()
                .http_status_as_error(false)
                .allow_non_standard_methods(true)
                .max_redirects(0)
                .max_redirects_will_error(false)
                .timeout_global(Some(Duration::from_secs(60)))
                .build()
                .into();
            let mut response = agent.run(request).map_err(|error| {
                log::warn!("webdav: {method} failed: {error}");
                DavError::Network
            })?;
            let status = response.status().as_u16();
            if matches!(status, 401 | 403) {
                return Err(DavError::Unauthorized);
            }
            // Bound hostile or accidentally huge downloads to 128 MiB.
            let limit = 128 * 1024 * 1024;
            let mut bytes = Vec::new();
            response
                .body_mut()
                .as_reader()
                .take(limit + 1)
                .read_to_end(&mut bytes)
                .map_err(|_| DavError::Network)?;
            if bytes.len() as u64 > limit {
                return Err(DavError::Status(413));
            }
            Ok((status, bytes))
        })
        .await
        .map_err(|_| DavError::Network)?
    }

    /// Puts `bytes` as `name` in the folder, creating the folder if the
    /// server says it is missing.
    pub async fn put(&self, name: &str, bytes: Vec<u8>) -> Result<(), DavError> {
        if !safe_name(name) {
            return Err(DavError::Status(0));
        }
        let base = self.base().ok_or(DavError::Status(0))?;
        let kind = [
            ("Content-Type", "application/octet-stream"),
            ("If-None-Match", "*"),
        ];
        let (status, _) = self
            .send("PUT", format!("{base}{name}"), bytes.clone(), &kind)
            .await?;
        let status = if matches!(status, 404 | 409) {
            let (made, _) = self.send("MKCOL", base.clone(), Vec::new(), &[]).await?;
            if !matches!(made, 200..=299 | 405) {
                return Err(DavError::Status(made));
            }
            self.send("PUT", format!("{base}{name}"), bytes, &kind)
                .await?
                .0
        } else {
            status
        };
        if (200..=299).contains(&status) {
            Ok(())
        } else {
            Err(DavError::Status(status))
        }
    }

    /// The backups in the folder, newest name first.
    pub async fn list(&self) -> Result<Vec<String>, DavError> {
        let base = self.base().ok_or(DavError::Status(0))?;
        let body = br#"<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getlastmodified/></d:prop></d:propfind>"#;
        let headers = [("Depth", "1"), ("Content-Type", "application/xml")];
        let (status, answer) = self.send("PROPFIND", base, body.to_vec(), &headers).await?;
        match status {
            207 | 200 => Ok(backup_names(&String::from_utf8_lossy(&answer))),
            404 => Ok(Vec::new()),
            status => Err(DavError::Status(status)),
        }
    }

    /// The backup `name`'s bytes.
    pub async fn get(&self, name: &str) -> Result<Vec<u8>, DavError> {
        if !safe_name(name) {
            return Err(DavError::Status(0));
        }
        let base = self.base().ok_or(DavError::Status(0))?;
        let (status, body) = self
            .send("GET", format!("{base}{name}"), Vec::new(), &[])
            .await?;
        if status == 200 {
            Ok(body)
        } else {
            Err(DavError::Status(status))
        }
    }
}

fn safe_name(name: &str) -> bool {
    name.starts_with("naviwealth-")
        && name.ends_with(&format!(".{EXTENSION}"))
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "-.".contains(c))
}

/// The backup file names in a PROPFIND answer, newest first (their names
/// carry the day, so name order is date order).
pub fn backup_names(xml: &str) -> Vec<String> {
    let suffix = format!(".{EXTENSION}");
    let mut names: Vec<String> = xml
        .split("href>")
        .skip(1)
        .filter_map(|part| part.split('<').next())
        .map(|href| href.trim().trim_end_matches('/'))
        .filter_map(|href| href.rsplit('/').next())
        .filter(|name| name.ends_with(&suffix) && safe_name(name))
        .map(str::to_owned)
        .collect();
    names.sort_unstable_by(|a, b| b.cmp(a));
    names.dedup();
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn listings_give_only_backup_names_newest_first() {
        let xml = r#"<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">
            <d:response><d:href>/dav/NaviWealth/</d:href></d:response>
            <d:response><d:href>/dav/NaviWealth/naviwealth-2026-11-12.nwbk</d:href></d:response>
            <D:response><D:href>https://dav.example.com/dav/NaviWealth/naviwealth-2026-11-13.nwbk</D:href></D:response>
            <d:response><d:href>/dav/NaviWealth/notes.txt</d:href></d:response>
            <d:response><d:href>/dav/NaviWealth/naviwealth-..%2Fx.nwbk</d:href></d:response>
        </d:multistatus>"#;
        assert_eq!(
            backup_names(xml),
            ["naviwealth-2026-11-13.nwbk", "naviwealth-2026-11-12.nwbk"]
        );
    }

    #[test]
    fn a_folder_needs_https_an_account_and_a_password() {
        let mut folder = Folder {
            url: "https://dav.jianguoyun.com/dav/NaviWealth//".into(),
            username: "me@example.com".into(),
            password: "app-password".into(),
        };
        assert_eq!(
            folder.base().as_deref(),
            Some("https://dav.jianguoyun.com/dav/NaviWealth/")
        );
        assert!(folder.is_complete());
        assert_eq!(
            folder.auth(),
            format!("Basic {}", B64.encode("me@example.com:app-password"))
        );
        folder.url = "http://dav.example.com/x".into();
        assert_eq!(folder.base(), None);
        folder.url = "http://127.0.0.1:8080/dav".into();
        assert!(folder.base().is_some());
        for invalid in [
            "http://127.0.0.1.evil.test/dav",
            "http://localhost.evil.test/dav",
            "https://user:password@example.com/dav",
            "https://example.com/dav?token=secret",
            "https://example.com/dav#part",
        ] {
            folder.url = invalid.into();
            assert!(folder.base().is_none(), "{invalid}");
        }
        folder.url = "https://example.com/dav".into();
        folder.password.clear();
        assert!(!folder.is_complete());
    }
}
