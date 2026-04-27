/// Vendor-agnostic crash & breadcrumb sink.
///
/// ## 选型
///
/// **NaviWealth uses Sentry** (rather than Firebase Crashlytics). Reasons:
///
/// 1. **Web parity.** Crashlytics' Flutter Web support is third-party / fragile;
///    Sentry's `sentry_flutter` ships first-class Web support including source
///    map upload. NaviWealth must run on iOS / Android / Web (FIR-2), so this
///    is decisive.
/// 2. **Backend uniformity.** The Cloudflare Workers + Rust backend (FIR-32 /
///    FIR-36) can also report to Sentry, giving a single dashboard for client
///    + server errors and shared release tags.
/// 3. **No Firebase footprint.** Adopting Crashlytics drags in google-services
///    config, FlutterFire init, and an extra Apple privacy-manifest entry —
///    all for a single feature. We avoid the platform tax.
/// 4. **Self-hostable later** if data-residency requirements change.
///
/// ## Wiring
///
/// The default app build uses [NoopCrashReporter] so unit tests and dev runs
/// don't ship telemetry. To enable Sentry in staging / prod, the integration
/// task (follow-up) will:
///   * add `sentry_flutter` to `pubspec.yaml`,
///   * add a `SentryCrashReporter` implementing this interface and call
///     `SentryFlutter.init(...)` from `bootstrap.dart`,
///   * register it via `crashReporterProvider` overrides keyed off
///     [AppEnvironment].
///
/// Until then this file is the contract: anything that wants to record errors
/// goes through [CrashReporter], not the vendor SDK directly.
abstract class CrashReporter {
  const CrashReporter();

  /// Report a thrown error / exception.
  void captureError(Object error, {StackTrace? stackTrace, String? hint});

  /// Report a non-error event (e.g. an assertion that we want to track).
  void captureMessage(String message, {BreadcrumbLevel level});

  /// Add a breadcrumb (no immediate upload — surfaces alongside the next
  /// captured error).
  void recordBreadcrumb({
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    String? category,
  });

  /// Attach the signed-in user. Pass `null` for [userId] on logout.
  void identifyUser({String? userId});
}

enum BreadcrumbLevel { debug, info, warning, error, fatal }

/// Default no-op implementation used in tests, dev runs, and any environment
/// without a configured DSN. Safe to leave installed in production — it just
/// drops events silently.
class NoopCrashReporter extends CrashReporter {
  const NoopCrashReporter();

  @override
  void captureError(Object error, {StackTrace? stackTrace, String? hint}) {}

  @override
  void captureMessage(
    String message, {
    BreadcrumbLevel level = BreadcrumbLevel.info,
  }) {}

  @override
  void recordBreadcrumb({
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    String? category,
  }) {}

  @override
  void identifyUser({String? userId}) {}
}
