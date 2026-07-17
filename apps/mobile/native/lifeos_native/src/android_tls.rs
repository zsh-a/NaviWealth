use anyhow::Result;
use std::sync::Once;

#[cfg(target_os = "android")]
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(target_os = "android")]
static ANDROID_TLS_VERIFIER_INITIALIZED: AtomicBool = AtomicBool::new(false);

static CRYPTO_PROVIDER_INIT: Once = Once::new();

fn ensure_crypto_provider() {
    CRYPTO_PROVIDER_INIT.call_once(|| {
        // reqwest currently selects aws-lc-rs. Installing it explicitly keeps
        // provider selection deterministic when the native crate is loaded by
        // a background Android process before any HTTP client is constructed.
        // An existing provider is acceptable (for example in a test host).
        let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
    });
}

#[cfg(target_os = "android")]
pub(crate) fn ensure_initialized() -> Result<()> {
    ensure_crypto_provider();
    if ANDROID_TLS_VERIFIER_INITIALIZED.load(Ordering::Acquire) {
        return Ok(());
    }
    anyhow::bail!(
        "Android TLS verifier is not initialized; native HTTP is unavailable until MainActivity initializes lifeos_native"
    );
}

#[cfg(not(target_os = "android"))]
pub(crate) fn ensure_initialized() -> Result<()> {
    ensure_crypto_provider();
    Ok(())
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_naviwealth_naviwealth_NaviWealthApplication_initLifeosNativeAndroid<
    'caller,
>(
    mut env: jni::EnvUnowned<'caller>,
    _this: jni::objects::JObject<'caller>,
    context: jni::objects::JObject<'caller>,
) -> jni::sys::jboolean {
    let outcome = env.with_env(|env| -> Result<jni::sys::jboolean, jni::errors::Error> {
        ensure_crypto_provider();
        rustls_platform_verifier::android::init_with_env(env, context)?;
        ANDROID_TLS_VERIFIER_INITIALIZED.store(true, Ordering::Release);
        Ok(jni::sys::JNI_TRUE)
    });
    outcome.resolve::<jni::errors::ThrowRuntimeExAndDefault>()
}

#[cfg(test)]
mod tests {
    #[test]
    fn process_crypto_provider_initializes_idempotently() {
        super::ensure_crypto_provider();
        super::ensure_crypto_provider();
        assert!(rustls::crypto::CryptoProvider::get_default().is_some());
    }
}
