/// Barrel for `lib/core/ai/local/embedding/`.
///
/// Embedder abstractions + implementations:
///
/// - `embedder.dart` — [Embedder] interface + [StubEmbedder] default
/// - `rust_gemma_embedder.dart` — production EmbeddingGemma-300M
///   via Rust + fastembed/ort + `flutter_rust_bridge`-generated
///   bindings + cargokit-managed native build (D-1.7c, opt-in via
///   `AppConfig`)
///
/// Vector store + Memory Runtime live in `lib/core/ai/local/memory/`.
library;

export 'embedder.dart';
export 'rust_gemma_embedder.dart'
    show RustGemmaEmbedder, RustEmbedderUnavailable, initLifeosNativeRuntime;
