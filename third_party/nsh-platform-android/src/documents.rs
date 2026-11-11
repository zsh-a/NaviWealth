//! Document exchange through Android's Storage Access Framework. The system
//! chooses a content URI; Java copies bytes so Rust never treats it as a path.

use jni::{
    JNIEnv,
    objects::{JClass, JString, JValue},
};
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};
use tokio::sync::oneshot;

type ResultPath = Result<Option<PathBuf>, String>;
struct Reply {
    result: ResultPath,
    cleanup: bool,
}
impl Reply {
    fn take(mut self) -> ResultPath {
        self.cleanup = false;
        std::mem::replace(&mut self.result, Ok(None))
    }
}
impl Drop for Reply {
    fn drop(&mut self) {
        if self.cleanup
            && let Ok(Some(path)) = &self.result
        {
            let _ = std::fs::remove_file(path);
        }
    }
}
struct PendingRequest {
    sender: oneshot::Sender<Reply>,
    cleanup: bool,
}
type Pending = HashMap<u64, PendingRequest>;
static NEXT: AtomicU64 = AtomicU64::new(1);
static PENDING: OnceLock<Mutex<Pending>> = OnceLock::new();
fn pending() -> &'static Mutex<Pending> {
    PENDING.get_or_init(Mutex::default)
}

struct Request(u64);
impl Drop for Request {
    fn drop(&mut self) {
        if let Ok(mut pending) = pending().lock() {
            pending.remove(&self.0);
        }
    }
}

/// Whether this runner includes the document bridge. Older prebuilt DEX files
/// return false, allowing callers to explain the missing platform capability.
pub fn available() -> bool {
    crate::java::java().backup_files.is_some()
        && crate::APP_DOCUMENT_VIEW.with(|view| view.borrow().is_some())
}

/// Copy an already encrypted local file to a document chosen by the user.
/// Call on the engine thread. `None` means the user cancelled the picker.
pub async fn export_file(source: PathBuf, suggested_name: String) -> ResultPath {
    document(Some(source), suggested_name, false).await
}

/// Choose an encrypted backup and copy it to app-private temporary storage.
/// The caller must remove the returned staging file after reading it.
/// Call on the engine thread. `None` means the user cancelled the picker.
pub async fn import_file() -> ResultPath {
    document(None, String::new(), false).await
}

/// Choose a CSV statement (10,000,000 bytes maximum). The returned app-private
/// staging file belongs to the caller and must be removed after reading.
pub async fn import_statement_csv() -> ResultPath {
    document(None, String::new(), true).await
}

async fn document(source: Option<PathBuf>, suggested_name: String, statement: bool) -> ResultPath {
    let class = crate::java::java()
        .backup_files
        .as_ref()
        .ok_or_else(|| "当前版本暂不支持系统文件选择；可先创建本机副本。".to_owned())?;
    let view = crate::APP_DOCUMENT_VIEW
        .with(|view| view.borrow().clone())
        .ok_or_else(|| "文件选择必须从应用界面打开".to_owned())?;
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let (tx, rx) = oneshot::channel();
    pending()
        .lock()
        .map_err(|_| "文件请求不可用".to_owned())?
        .insert(
            id,
            PendingRequest {
                sender: tx,
                cleanup: source.is_none(),
            },
        );
    let _request = Request(id);
    let result = crate::java::with_env(|env| {
        let path = env.new_string(
            source
                .as_ref()
                .map(|path| path.to_string_lossy().into_owned())
                .unwrap_or_default(),
        )?;
        let name = env.new_string(suggested_name)?;
        let class: &JClass<'_> = class.as_obj().into();
        if statement {
            let purpose = env.new_string("CSV账单")?;
            let mime = env.new_string("text/csv")?;
            let suffix = env.new_string(".csv")?;
            env.call_static_method(class,"chooseImport","(Lcom/longbridge/nsh/NshView;JLjava/lang/String;Ljava/lang/String;JLjava/lang/String;)V",&[JValue::Object(view.as_obj()),JValue::Long(id as i64),JValue::Object(&purpose),JValue::Object(&mime),JValue::Long(10_000_000),JValue::Object(&suffix)])?;
        } else {
            env.call_static_method(
                class,
                "choose",
                "(Lcom/longbridge/nsh/NshView;JLjava/lang/String;Ljava/lang/String;)V",
                &[
                    JValue::Object(view.as_obj()),
                    JValue::Long(id as i64),
                    JValue::Object(&path),
                    JValue::Object(&name),
                ],
            )?;
        }
        Ok(true)
    });
    if !result {
        return Err("无法打开系统文件选择器".to_owned());
    }
    rx.await.map_err(|_| "文件选择已结束".to_owned())?.take()
}

#[unsafe(no_mangle)]
extern "system" fn Java_com_longbridge_nsh_BackupFiles_complete(
    mut env: JNIEnv<'_>,
    _: JClass<'_>,
    id: i64,
    path: JString<'_>,
    error: JString<'_>,
) -> jni::sys::jboolean {
    let result = if !error.is_null() {
        Err(env
            .get_string(&error)
            .map(String::from)
            .unwrap_or_else(|_| "文件操作失败".to_owned()))
    } else if path.is_null() {
        Ok(None)
    } else {
        env.get_string(&path)
            .map(|path| Some(PathBuf::from(String::from(path))))
            .map_err(|_| "文件路径不可用".to_owned())
    };
    if let Ok(mut pending) = pending().lock()
        && let Some(request) = pending.remove(&(id as u64))
    {
        return if request
            .sender
            .send(Reply {
                result,
                cleanup: request.cleanup,
            })
            .is_ok()
        {
            jni::sys::JNI_TRUE
        } else {
            jni::sys::JNI_FALSE
        };
    }
    // Java deletes unclaimed imported staging files. Export sources are retained.
    jni::sys::JNI_FALSE
}
