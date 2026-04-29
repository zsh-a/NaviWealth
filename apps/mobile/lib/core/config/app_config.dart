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
    bypassAuth: bool.fromEnvironment('BYPASS_AUTH', defaultValue: true),
  );
}

enum AppEnvironment { dev, staging, prod }
