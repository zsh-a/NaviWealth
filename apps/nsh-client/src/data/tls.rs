//! NSH's Android host has no JavaVM for the platform verifier. Use the
//! bundled public roots with normal certificate and hostname verification.
use std::sync::Arc;

pub(super) fn config() -> Result<rustls::ClientConfig, rustls::Error> {
    let roots = rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    Ok(rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()?
    .with_root_certificates(roots)
    .with_no_client_auth())
}
