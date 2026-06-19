class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.environment,
    this.bypassAuth = false,
    this.sentryDsn = '',
    this.rustEmbedderModelDir = '',
    this.rustEmbedderLibraryPath = '',
    this.rustEmbedderOrtDylibPath = '',
  });

  final String apiBaseUrl;
  final AppEnvironment environment;

  /// Skip the login wall and let every route render without a session.
  /// Bootstrap honours this by not registering [AuthRouteGuard]. Dev-only —
  /// API calls that need a token will still 401 against a real backend.
  final bool bypassAuth;

  /// Optional Sentry DSN. Defaults to empty so unconfigured builds keep
  /// the [NoopCrashReporter] and never reach out to sentry.io. Inject in
  /// CI via `--dart-define=SENTRY_DSN=https://...@o0.ingest.sentry.io/0`.
  /// `roadmap-next.md` §8 picked Sentry SaaS over self-hosted.
  final String sentryDsn;

  bool get hasSentryDsn => sentryDsn.isNotEmpty;

  /// Path to a directory containing the EmbeddingGemma ONNX model +
  /// tokenizer JSON files (D-1.7c per `docs/lifeos-shell.md` §6.6).
  /// See `apps/mobile/native/lifeos_native/README.md` for the exact
  /// file list. Empty = use [StubEmbedder] default.
  ///
  /// Inject in dev/release via
  /// `--dart-define=RUST_EMBEDDER_MODEL_DIR=/abs/path/to/embeddinggemma-300m-ONNX`.
  final String rustEmbedderModelDir;

  /// Optional explicit path to `liblifeos_native.{dylib,so}`. Empty =
  /// use the cargokit-managed plugin loader (the production path —
  /// `flutter run` / `flutter build` bundles the lib automatically
  /// via the `rust_builder/` plugin).
  ///
  /// Only set this for `flutter test` runs on desktop, where the
  /// test harness doesn't go through the plugin loader and needs an
  /// explicit dylib path (e.g.
  /// `apps/mobile/native/lifeos_native/target/release/`).
  final String rustEmbedderLibraryPath;

  /// Path to `libonnxruntime.{dylib,so,dll}` for the Rust embedder.
  /// We use `ort-load-dynamic` to dodge the duplicate-symbol issue
  /// in ORT's prebuilt static archives, so this path is **required**
  /// when [rustEmbedderModelDir] is set.
  ///
  /// Download URLs in `apps/mobile/native/lifeos_native/README.md`.
  /// Inject via
  /// `--dart-define=RUST_EMBEDDER_ORT_DYLIB_PATH=/abs/path/to/libonnxruntime.dylib`.
  final String rustEmbedderOrtDylibPath;

  bool get hasRustEmbedder => rustEmbedderModelDir.isNotEmpty;

  static const AppConfig dev = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8787',
    ),
    environment: AppEnvironment.dev,
    bypassAuth: bool.fromEnvironment('BYPASS_AUTH', defaultValue: false),
    sentryDsn: String.fromEnvironment('SENTRY_DSN', defaultValue: ''),
    rustEmbedderModelDir: String.fromEnvironment(
      'RUST_EMBEDDER_MODEL_DIR',
      defaultValue: '',
    ),
    rustEmbedderLibraryPath: String.fromEnvironment(
      'RUST_EMBEDDER_LIBRARY_PATH',
      defaultValue: '',
    ),
    rustEmbedderOrtDylibPath: String.fromEnvironment(
      'RUST_EMBEDDER_ORT_DYLIB_PATH',
      defaultValue: '',
    ),
  );
}

enum AppEnvironment { dev, staging, prod }
