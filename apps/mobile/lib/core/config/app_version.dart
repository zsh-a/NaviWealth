import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Build-time identity of the running binary. `version` and `buildNumber`
/// come from the platform package metadata via `package_info_plus`;
/// `commitSha` is injected at compile time with `--dart-define=GIT_SHA=...`
/// from CI (`tool/bump-version.sh` / `release.yml`).
class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.commitSha,
  });

  final String version;
  final String buildNumber;
  final String commitSha;

  /// Compile-time SHA from `--dart-define=GIT_SHA=...`. `dev` when the
  /// binary was built locally without the define.
  static const String _embeddedSha = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: 'dev',
  );

  static AppVersionInfo fromPackage(PackageInfo info) => AppVersionInfo(
        version: info.version,
        buildNumber: info.buildNumber,
        commitSha: _embeddedSha,
      );
}

/// Runtime app version, build number, and commit SHA. Resolved once at
/// startup (`PackageInfo.fromPlatform` reads from native `Info.plist` /
/// `AndroidManifest.xml` / web `version.json`).
final appVersionProvider = FutureProvider<AppVersionInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersionInfo.fromPackage(info);
});
