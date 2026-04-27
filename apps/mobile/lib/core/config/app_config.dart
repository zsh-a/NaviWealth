class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.environment});

  final String apiBaseUrl;
  final AppEnvironment environment;

  static const AppConfig dev = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8787',
    ),
    environment: AppEnvironment.dev,
  );
}

enum AppEnvironment { dev, staging, prod }
