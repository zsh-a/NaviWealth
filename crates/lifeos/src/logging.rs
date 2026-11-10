//! Development logging. Structured logs are for development only and must
//! never contain secrets, financial details, health content or voice text —
//! call sites log ids, counts and durations.

/// Initialize a compact tracing subscriber (`RUST_LOG` filters, default
/// `info`). The nsh app calls this at startup on native targets.
pub fn init_dev_logging() {
    #[cfg(feature = "dev-logs")]
    {
        use tracing_subscriber::EnvFilter;
        let _ =
            tracing_subscriber::fmt()
                .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| {
                    EnvFilter::new("info,lifeos=debug,naviwealth_finance=debug")
                }))
                .try_init();
    }
    #[cfg(not(feature = "dev-logs"))]
    {
        // Compiled out: the app crate owns its own subscriber.
    }
}
