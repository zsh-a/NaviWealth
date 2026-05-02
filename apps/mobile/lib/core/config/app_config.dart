class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.environment,
    this.bypassAuth = false,
  });

  final String apiBaseUrl;
  final AppEnvironment environment;

  /// Skip the login wall and let every route render without a session.
  /// Bootstrap honours this by not registering [AuthRouteGuard]. Dev-only —
  /// API calls that need a token will still 401 against a real backend.
  final bool bypassAuth;

  static const AppConfig dev = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8787',
    ),
    environment: AppEnvironment.dev,
    bypassAuth: bool.fromEnvironment('BYPASS_AUTH', defaultValue: false),
  );
}

enum AppEnvironment { dev, staging, prod }

/// Semver of this build, stamped at compile time by the release workflow
/// (and `tool/bump-version.sh` for tagged dev builds). Falls back to a
/// dev-friendly placeholder when the define is missing so unstamped local
/// builds don't ship the wrong number to the about screen.
///
/// Pass at build time:
///   flutter build web --dart-define APP_VERSION=0.2.0
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'dev',
);
