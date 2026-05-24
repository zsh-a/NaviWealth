//! EmbeddingGemma-300M (ONNX INT8) embedder, exposed to Dart via
//! `flutter_rust_bridge` (D-1.7c per `docs/lifeos-shell.md` §6.6).
//!
//! Public surface is intentionally small (per `lifeos-shell.md` §10):
//!
//! - [`GemmaEmbedder::load`]        — async constructor (model warm-up)
//! - [`GemmaEmbedder::embed`]       — async per-text embedding
//! - [`GemmaEmbedder::dimension`]   — sync constant (always 768)
//! - [`GemmaEmbedder::fingerprint`] — sync constant string
//!
//! FRB auto-generates the matching Dart class + serialisation.
//! Result<T, anyhow::Error> on the Rust side becomes a Future that
//! throws a Dart exception carrying the error message.
//!
//! Required files in `model_dir`:
//!
//! | File                       | Source                                                                                      |
//! |----------------------------|---------------------------------------------------------------------------------------------|
//! | `model_int8.onnx`          | https://huggingface.co/onnx-community/embeddinggemma-300m-ONNX (INT8 quantised variant)     |
//! | `tokenizer.json`           | same repo                                                                                   |
//! | `config.json`              | same repo                                                                                   |
//! | `special_tokens_map.json`  | same repo                                                                                   |
//! | `tokenizer_config.json`    | same repo                                                                                   |
//!
//! Threadsafety: `TextEmbedding` is `Send + Sync` (via Mutex);
//! concurrent calls to `embed` are serialised by ORT's session.

use anyhow::{anyhow, Context, Result};
use fastembed::{
    InitOptionsUserDefined, Pooling, TextEmbedding, TokenizerFiles,
    UserDefinedEmbeddingModel,
};
use flutter_rust_bridge::frb;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// Stable identifier for this model + version + quantisation. Persisted
/// alongside every stored vector so the store can drop rows produced
/// by a different embedder.
pub const MODEL_FINGERPRINT: &str = "embeddinggemma-300m-onnx-int8-d768";

/// Output dimension. Constant for EmbeddingGemma; exposed via
/// [`GemmaEmbedder::dimension`] for Dart-side sanity checks.
pub const EMBEDDING_DIM: u32 = 768;

#[frb(opaque)]
pub struct GemmaEmbedder {
    // fastembed's `TextEmbedding::embed` takes `&mut self`. We hand
    // out shared references over FRB so we serialise inference behind
    // a `Mutex`. ONNX Runtime sessions are already serialised
    // internally, so the mutex isn't masking real parallelism.
    inner: Mutex<TextEmbedding>,
}

impl GemmaEmbedder {
    /// Load the embedder from `model_dir`. Slow (~seconds for ONNX
    /// session warm-up); FRB makes this `Future<GemmaEmbedder>` on
    /// the Dart side automatically.
    ///
    /// `ort_dylib_path` points at `libonnxruntime.{dylib,so,dll}` —
    /// we use the `ort-load-dynamic` flavour to avoid the duplicate
    /// `.o` files that ORT's prebuilt static archives contain (which
    /// would surface as ~756 "duplicate symbol" linker errors when
    /// force-loaded into the Flutter app). Pass an empty string to
    /// fall back to whatever `ORT_DYLIB_PATH` env var is already
    /// set in the process (useful for tests).
    pub fn load(
        model_dir: String,
        ort_dylib_path: String,
    ) -> Result<GemmaEmbedder> {
        if !ort_dylib_path.is_empty() {
            // Must be set before ANY ort:: call; fastembed::TextEmbedding
            // touches the runtime in `try_new_from_user_defined` below.
            // SAFETY: single-threaded init path; no concurrent readers
            // of this env at construction time.
            unsafe {
                std::env::set_var("ORT_DYLIB_PATH", &ort_dylib_path);
            }
        }
        let dir = PathBuf::from(model_dir);
        if dir.as_os_str().is_empty() {
            return Err(anyhow!("model_dir is empty"));
        }
        let onnx_path = pick_onnx_path(&dir)?;
        let onnx_bytes = std::fs::read(&onnx_path)
            .with_context(|| format!("failed to read {}", onnx_path.display()))?;

        let tokenizer_files = TokenizerFiles {
            tokenizer_file: read_required(&dir, "tokenizer.json")?,
            config_file: read_required(&dir, "config.json")?,
            special_tokens_map_file: read_required(
                &dir,
                "special_tokens_map.json",
            )?,
            tokenizer_config_file: read_required(
                &dir,
                "tokenizer_config.json",
            )?,
        };

        let mut user_model =
            UserDefinedEmbeddingModel::new(onnx_bytes, tokenizer_files)
                .with_pooling(Pooling::Mean);

        // EmbeddingGemma's quantized ONNX export splits weights into
        // an external `.onnx_data` blob (the .onnx itself is just the
        // graph). When fastembed feeds the .onnx bytes to ORT via
        // `commit_from_memory`, ORT has no directory context to
        // resolve relative external_data paths — we must register
        // the blob explicitly through `with_external_initializer`.
        // The `file_name` must match the relative path the .onnx
        // references (just the filename when both files sit in the
        // same dir, which is our installer convention).
        let onnx_data_path = {
            let mut p = onnx_path.clone();
            let file_name = p
                .file_name()
                .and_then(|n| n.to_str())
                .map(|n| format!("{n}_data"))
                .ok_or_else(|| anyhow!("invalid onnx path"))?;
            p.set_file_name(&file_name);
            p
        };
        if onnx_data_path.is_file() {
            let blob = std::fs::read(&onnx_data_path).with_context(|| {
                format!("failed to read {}", onnx_data_path.display())
            })?;
            let file_name = onnx_data_path
                .file_name()
                .and_then(|n| n.to_str())
                .map(String::from)
                .ok_or_else(|| anyhow!("invalid onnx_data path"))?;
            user_model = user_model.with_external_initializer(file_name, blob);
        }

        let inner = TextEmbedding::try_new_from_user_defined(
            user_model,
            InitOptionsUserDefined::default(),
        )
        .map_err(|e| anyhow!("fastembed init failed: {e}"))?;

        Ok(GemmaEmbedder {
            inner: Mutex::new(inner),
        })
    }

    /// Output dimension. Always 768 for EmbeddingGemma-300M; the
    /// `#[frb(sync)]` hint makes this a plain `int` getter on Dart.
    #[frb(sync)]
    pub fn dimension(&self) -> u32 {
        EMBEDDING_DIM
    }

    /// Stable identifier. The Memory Layer persists this with every
    /// embedding so swapping models invalidates the vectors.
    #[frb(sync)]
    pub fn fingerprint(&self) -> String {
        MODEL_FINGERPRINT.to_string()
    }

    /// Embed `text` into a unit-length 768-d vector. fastembed
    /// L2-normalises by default; we sanity-check the dimension to
    /// catch model/config mismatches early.
    pub fn embed(&self, text: String) -> Result<Vec<f32>> {
        if text.is_empty() {
            return Ok(vec![0.0; EMBEDDING_DIM as usize]);
        }
        let mut inner = self
            .inner
            .lock()
            .map_err(|e| anyhow!("embedder mutex poisoned: {e}"))?;
        let mut batches = inner
            .embed(vec![text.as_str()], None)
            .map_err(|e| anyhow!("fastembed embed failed: {e}"))?;
        if batches.is_empty() {
            return Err(anyhow!("fastembed returned empty batch"));
        }
        let vec = batches.remove(0);
        if vec.len() != EMBEDDING_DIM as usize {
            return Err(anyhow!(
                "embedding dim mismatch: expected {EMBEDDING_DIM}, got {}",
                vec.len()
            ));
        }
        Ok(vec)
    }
}

/// EmbeddingGemma's ONNX exports come in several quantisations.
/// Prefer the INT8 `model_quantized` variant (smallest while keeping
/// quality close to FP32); fall back to other available variants if
/// the user picked a different one. `model.onnx` (FP32) is the last
/// resort.
///
/// `onnx-community/embeddinggemma-300m-ONNX` uses the
/// `model_quantized.onnx` naming (matched by `optimum-exporter` for
/// transformers ≥4.30). Older `model_int8.onnx` is kept as a
/// fallback in case a future re-export uses that name.
fn pick_onnx_path(model_dir: &Path) -> Result<PathBuf> {
    for name in [
        "model_quantized.onnx",
        "model_int8.onnx",
        "model_uint8.onnx",
        "model_q4.onnx",
        "model_fp16.onnx",
        "model.onnx",
    ] {
        let candidate = model_dir.join(name);
        if candidate.is_file() {
            return Ok(candidate);
        }
    }
    Err(anyhow!(
        "no ONNX weights found in {}; expected model_quantized.onnx",
        model_dir.display()
    ))
}

fn read_required(model_dir: &Path, name: &str) -> Result<Vec<u8>> {
    let path = model_dir.join(name);
    std::fs::read(&path).with_context(|| format!("failed to read {}", path.display()))
}

// Module-level functions are also visible to FRB; keep them for
// trivial sanity probes the Dart side can call without holding a
// `GemmaEmbedder` handle.

#[frb(sync)]
pub fn embedding_dim() -> u32 {
    EMBEDDING_DIM
}

#[frb(sync)]
pub fn embedder_fingerprint() -> String {
    MODEL_FINGERPRINT.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn constants_match() {
        assert_eq!(embedding_dim(), 768);
        assert_eq!(embedder_fingerprint(), "embeddinggemma-300m-onnx-int8-d768");
    }

    #[test]
    fn empty_model_dir_errors() {
        // GemmaEmbedder is `#[frb(opaque)]` and doesn't impl Debug
        // (TextEmbedding doesn't either), so use pattern matching
        // instead of `unwrap_err()`.
        match GemmaEmbedder::load(String::new(), String::new()) {
            Ok(_) => panic!("expected load to fail on empty model_dir"),
            Err(e) => assert!(
                e.to_string().contains("empty"),
                "got: {e}"
            ),
        }
    }

    #[test]
    fn missing_model_dir_errors() {
        match GemmaEmbedder::load(
            "/definitely/does/not/exist".to_string(),
            String::new(),
        ) {
            Ok(_) => panic!("expected load to fail on missing dir"),
            Err(e) => {
                let msg = e.to_string();
                assert!(
                    msg.contains("does not exist") || msg.contains("no ONNX"),
                    "got: {msg}"
                );
            }
        }
    }
}
