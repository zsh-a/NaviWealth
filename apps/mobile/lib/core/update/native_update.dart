import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';
import '../config/providers.dart';
import 'native_update_errors.dart';
import 'native_update_file_store.dart';
import 'native_update_installer.dart';

const String kNativeUpdateDismissedVersionKey =
    'naviwealth.update.native.dismissed_version';
const String _kNativeUpdateManifestCacheKey =
    'naviwealth.update.native.github.manifest';
const String _kNativeUpdateManifestFetchedAtKey =
    'naviwealth.update.native.github.manifest_fetched_at';
const String _kNativeUpdateManifestSourceKey =
    'naviwealth.update.native.github.manifest_source';

const Duration _kNativeUpdateCacheTtl = Duration(hours: 12);

final packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

final nativeUpdateClientProvider = Provider<GitHubNativeUpdateClient>((ref) {
  final client = GitHubNativeUpdateClient();
  ref.onDispose(client.dispose);
  return client;
});

final nativeUpdateServiceProvider = Provider<NativeUpdateService>((ref) {
  return NativeUpdateService(
    installer: ref.watch(nativeUpdateInstallerProvider),
  );
});

final nativeUpdateStateProvider = FutureProvider<NativeUpdateState>((
  ref,
) async {
  if (!_isAndroidNativePlatform) return NativeUpdateState.hidden;

  final config = ref.watch(appConfigProvider);
  if (!config.hasNativeUpdateTarget) return NativeUpdateState.hidden;

  final packageInfo = await ref.watch(packageInfoProvider.future);
  final prefs = ref.watch(sharedPreferencesProvider);
  final manifest = await ref
      .watch(nativeUpdateClientProvider)
      .fetchLatest(
        manifestUrl: config.nativeUpdateManifestUrl,
        preferences: prefs,
      );
  if (manifest == null || !manifest.isAndroid) {
    return NativeUpdateState.hidden;
  }

  final currentVersion = packageInfo.version.trim();
  final currentBuildNumber = packageInfo.buildNumber.trim();
  final currentBuild = int.tryParse(currentBuildNumber);
  final hasNewerBuild = currentBuild != null
      ? isNativeBuildNewer(manifest.versionCode, currentBuild)
      : isNativeUpdateNewer(manifest.versionName, currentVersion);
  if (!hasNewerBuild) return NativeUpdateState.hidden;

  final dismissed =
      prefs.getString(kNativeUpdateDismissedVersionKey) ==
          manifest.versionKey &&
      !manifest.mandatory;
  final required =
      manifest.mandatory ||
      (currentBuild != null &&
          manifest.minSupportedVersionCode != null &&
          currentBuild < manifest.minSupportedVersionCode!);

  return NativeUpdateState(
    currentVersion: currentVersion,
    currentBuildNumber: currentBuildNumber,
    manifest: manifest,
    requiredUpdate: required,
    shouldShow: !dismissed,
  );
});

bool get _isAndroidNativePlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

/// Metadata published as `latest.json` on the latest GitHub Release.
final class NativeUpdateManifest {
  const NativeUpdateManifest({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.mandatory,
    required this.releaseNotes,
    this.minSupportedVersionCode,
    this.sizeBytes,
    this.platform = 'android',
    this.channel = 'github',
  });

  final String versionName;
  final int versionCode;
  final Uri apkUrl;
  final String sha256;
  final bool mandatory;
  final List<String> releaseNotes;
  final int? minSupportedVersionCode;
  final int? sizeBytes;
  final String platform;
  final String channel;

  bool get isAndroid => platform.toLowerCase() == 'android';

  String get versionKey => '$versionName+$versionCode';

  static NativeUpdateManifest? tryParse(Object? value) {
    if (value is! Map) return null;

    final versionName = _stringValue(value['versionName']);
    final versionCode = _intValue(value['versionCode']);
    final apkUrl = _uriValue(value['apkUrl'] ?? value['url']);
    final sha256 = _stringValue(value['sha256'])?.toLowerCase();
    if (versionName == null ||
        versionName.isEmpty ||
        versionCode == null ||
        versionCode <= 0 ||
        apkUrl == null ||
        !_isSafeGithubUrl(apkUrl) ||
        sha256 == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      return null;
    }

    final rawNotes = value['releaseNotes'];
    final notes = rawNotes is List
        ? rawNotes
              .whereType<String>()
              .map((note) => note.trim())
              .where((note) => note.isNotEmpty)
              .take(8)
              .toList(growable: false)
        : const <String>[];
    final platform = _stringValue(value['platform']) ?? 'android';
    final channel = _stringValue(value['channel']) ?? 'github';
    final minSupported = _intValue(value['minSupportedVersionCode']);
    final sizeBytes = _intValue(value['size']);

    return NativeUpdateManifest(
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: apkUrl,
      sha256: sha256,
      mandatory: value['mandatory'] == true,
      releaseNotes: notes,
      minSupportedVersionCode: minSupported != null && minSupported > 0
          ? minSupported
          : null,
      sizeBytes: sizeBytes != null && sizeBytes > 0 ? sizeBytes : null,
      platform: platform,
      channel: channel,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'platform': platform,
    'channel': channel,
    'versionName': versionName,
    'versionCode': versionCode,
    if (minSupportedVersionCode != null)
      'minSupportedVersionCode': minSupportedVersionCode,
    'apkUrl': apkUrl.toString(),
    'sha256': sha256,
    if (sizeBytes != null) 'size': sizeBytes,
    'mandatory': mandatory,
    'releaseNotes': releaseNotes,
  };
}

/// Reads and caches the public GitHub Release manifest.
final class GitHubNativeUpdateClient {
  GitHubNativeUpdateClient({Dio? dio, DateTime Function()? now})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 15),
              followRedirects: true,
              maxRedirects: 5,
              headers: const <String, Object>{
                'Accept': 'application/json',
                'User-Agent': 'NaviWealth',
              },
            ),
          ),
      _now = now ?? DateTime.now;

  final Dio _dio;
  final DateTime Function() _now;

  Future<NativeUpdateManifest?> fetchLatest({
    required String manifestUrl,
    required SharedPreferences preferences,
  }) async {
    final source = manifestUrl.trim();
    if (!_isSafeManifestUrl(source)) return null;

    final cached = _readCached(preferences, source);
    final fetchedAtMs = preferences.getInt(_kNativeUpdateManifestFetchedAtKey);
    if (cached != null && fetchedAtMs != null) {
      final age = _now().difference(
        DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
      );
      if (age >= Duration.zero && age < _kNativeUpdateCacheTtl) {
        return cached;
      }
    }

    try {
      final response = await _dio.get<Object?>(source);
      final payload = response.data is String
          ? jsonDecode(response.data! as String)
          : response.data;
      final manifest = NativeUpdateManifest.tryParse(payload);
      if (manifest == null || !manifest.isAndroid) return cached;
      await preferences.setString(
        _kNativeUpdateManifestCacheKey,
        jsonEncode(manifest.toJson()),
      );
      await preferences.setString(_kNativeUpdateManifestSourceKey, source);
      await preferences.setInt(
        _kNativeUpdateManifestFetchedAtKey,
        _now().millisecondsSinceEpoch,
      );
      return manifest;
    } on Object {
      // Version checks are advisory. A cached manifest is safe to use for a
      // short period when GitHub is offline; a failed network request must
      // never block app startup or the rest of the product.
      return cached;
    }
  }

  NativeUpdateManifest? _readCached(
    SharedPreferences preferences,
    String source,
  ) {
    if (preferences.getString(_kNativeUpdateManifestSourceKey) != source) {
      return null;
    }
    final raw = preferences.getString(_kNativeUpdateManifestCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return NativeUpdateManifest.tryParse(jsonDecode(raw));
    } on Object {
      return null;
    }
  }

  void dispose() => _dio.close(force: true);
}

final class NativeUpdateState {
  const NativeUpdateState({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.manifest,
    required this.requiredUpdate,
    required this.shouldShow,
  });

  static const hidden = NativeUpdateState(
    currentVersion: '',
    currentBuildNumber: '',
    manifest: null,
    requiredUpdate: false,
    shouldShow: false,
  );

  final String currentVersion;
  final String currentBuildNumber;
  final NativeUpdateManifest? manifest;
  final bool requiredUpdate;
  final bool shouldShow;

  String get latestVersion => manifest?.versionName ?? '';

  String get updateUrl => manifest?.apkUrl.toString() ?? '';

  List<String> get releaseNotes => manifest?.releaseNotes ?? const <String>[];

  int? get sizeBytes => manifest?.sizeBytes;

  String get versionKey => manifest?.versionKey ?? '';
}

final class NativeUpdateService {
  NativeUpdateService({
    required NativeUpdateInstaller installer,
    NativeUpdateFileStore? fileStore,
    Dio? dio,
  }) : _installer = installer,
       _fileStore = fileStore ?? createNativeUpdateFileStore(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 30),
               followRedirects: true,
               maxRedirects: 5,
             ),
           );

  final NativeUpdateInstaller _installer;
  final NativeUpdateFileStore _fileStore;
  final Dio _dio;

  Future<void> downloadAndInstall(
    NativeUpdateManifest manifest, {
    void Function(int received, int total)? onProgress,
  }) async {
    final canInstall = await _installer.canInstallPackages();
    if (!canInstall) {
      throw const NativeUpdateException(NativeUpdateFailure.installPermission);
    }

    late final String apkPath;
    try {
      apkPath = await _fileStore.download(
        dio: _dio,
        url: manifest.apkUrl,
        versionKey: manifest.versionKey,
        onProgress: onProgress,
      );
    } on NativeUpdateException {
      rethrow;
    } on Object catch (error) {
      throw NativeUpdateException(NativeUpdateFailure.download, cause: error);
    }
    final actualSha256 = await _fileStore.sha256File(apkPath);
    if (actualSha256.toLowerCase() != manifest.sha256.toLowerCase()) {
      await _fileStore.delete(apkPath);
      throw const NativeUpdateException(NativeUpdateFailure.integrity);
    }

    try {
      await _installer.installApk(apkPath);
    } on Object {
      // Keep the verified file for a retry. The system installer may be
      // cancelled by the user after the method channel has returned.
      rethrow;
    }
  }
}

bool isNativeUpdateNewer(String latestVersion, String currentVersion) {
  final latest = _parseVersion(latestVersion);
  final current = _parseVersion(currentVersion);
  if (latest.isEmpty || current.isEmpty) return false;

  final count = latest.length > current.length ? latest.length : current.length;
  for (var i = 0; i < count; i++) {
    final left = i < latest.length ? latest[i] : 0;
    final right = i < current.length ? current[i] : 0;
    if (left > right) return true;
    if (left < right) return false;
  }
  return false;
}

bool isNativeBuildNewer(int latestBuild, int currentBuild) =>
    latestBuild > 0 && currentBuild >= 0 && latestBuild > currentBuild;

List<int> _parseVersion(String value) {
  final normalized = value.trim().split('+').first.split('-').first;
  if (normalized.isEmpty) return const [];
  final parts = <int>[];
  for (final raw in normalized.split('.')) {
    final match = RegExp(r'^\d+').firstMatch(raw);
    if (match == null) return const [];
    parts.add(int.parse(match.group(0)!));
  }
  return parts;
}

String? _stringValue(Object? value) => value is String ? value.trim() : null;

int? _intValue(Object? value) => switch (value) {
  int value => value,
  num value when value == value.roundToDouble() => value.toInt(),
  String value => int.tryParse(value.trim()),
  _ => null,
};

Uri? _uriValue(Object? value) {
  if (value is! String) return null;
  return Uri.tryParse(value.trim());
}

bool _isSafeManifestUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host == 'github.com';
}

bool _isSafeGithubUrl(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'github.com' || uri.host.endsWith('.github.com'));
