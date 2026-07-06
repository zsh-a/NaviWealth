use anyhow::Result;

#[cfg(target_os = "android")]
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(target_os = "android")]
static ANDROID_TLS_VERIFIER_INITIALIZED: AtomicBool = AtomicBool::new(false);

#[cfg(target_os = "android")]
pub(crate) fn ensure_initialized() -> Result<()> {
    if ANDROID_TLS_VERIFIER_INITIALIZED.load(Ordering::Acquire) {
        return Ok(());
    }
    anyhow::bail!(
        "Android TLS verifier is not initialized; native HTTP is unavailable until MainActivity initializes lifeos_native"
    );
}

#[cfg(not(target_os = "android"))]
pub(crate) fn ensure_initialized() -> Result<()> {
    Ok(())
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_naviwealth_naviwealth_MainActivity_initLifeosNativeAndroid<
    'caller,
>(
    mut env: jni::EnvUnowned<'caller>,
    _this: jni::objects::JObject<'caller>,
    context: jni::objects::JObject<'caller>,
) -> jni::sys::jboolean {
    let outcome = env.with_env(|env| -> Result<jni::sys::jboolean, jni::errors::Error> {
        rustls_platform_verifier::android::init_with_env(env, context)?;
        ANDROID_TLS_VERIFIER_INITIALIZED.store(true, Ordering::Release);
        Ok(jni::sys::JNI_TRUE)
    });
    outcome.resolve::<jni::errors::ThrowRuntimeExAndDefault>()
}
