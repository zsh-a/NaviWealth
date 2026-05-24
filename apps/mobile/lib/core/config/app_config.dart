class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.environment,
    this.bypassAuth = false,
    this.sentryDsn = '',
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
  /// `roadmap-next.md` §8 picked Sentry SaaS over self-hosted; the actual
  /// `sentry_flutter` dependency lands together with the DSN secret.
  final String sentryDsn;

  bool get hasSentryDsn => sentryDsn.isNotEmpty;

  static const AppConfig dev = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8787',
    ),
    environment: AppEnvironment.dev,
    bypassAuth: bool.fromEnvironment('BYPASS_AUTH', defaultValue: false),
    sentryDsn: String.fromEnvironment('SENTRY_DSN', defaultValue: ''),
  );
}

enum AppEnvironment { dev, staging, prod }
