import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/update/native_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('isNativeUpdateNewer', () {
    test('detects higher major minor and patch versions', () {
      expect(isNativeUpdateNewer('1.0.0', '0.9.9'), isTrue);
      expect(isNativeUpdateNewer('0.8.0', '0.7.9'), isTrue);
      expect(isNativeUpdateNewer('0.7.1', '0.7.0'), isTrue);
    });

    test('treats equal or older versions as not updateable', () {
      expect(isNativeUpdateNewer('0.7.0', '0.7.0'), isFalse);
      expect(isNativeUpdateNewer('0.7', '0.7.0'), isFalse);
      expect(isNativeUpdateNewer('0.6.9', '0.7.0'), isFalse);
    });

    test('ignores build metadata and prerelease suffixes', () {
      expect(isNativeUpdateNewer('0.8.0+42', '0.7.0+1'), isTrue);
      expect(isNativeUpdateNewer('0.8.0-beta.1', '0.8.0'), isFalse);
    });

    test('rejects empty and malformed versions', () {
      expect(isNativeUpdateNewer('', '0.7.0'), isFalse);
      expect(isNativeUpdateNewer('latest', '0.7.0'), isFalse);
      expect(isNativeUpdateNewer('0.8.0', ''), isFalse);
    });
  });

  group('isNativeBuildNewer', () {
    test('uses Android build numbers as the update ordering key', () {
      expect(isNativeBuildNewer(125, 124), isTrue);
      expect(isNativeBuildNewer(125, 125), isFalse);
      expect(isNativeBuildNewer(124, 125), isFalse);
    });
  });

  group('NativeUpdateManifest', () {
    const sha =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('parses a signed-by-release hash manifest', () {
      final manifest = NativeUpdateManifest.tryParse(<String, Object?>{
        'schemaVersion': 1,
        'platform': 'android',
        'channel': 'github',
        'versionName': '0.8.50',
        'versionCode': 125,
        'apkUrl': 'https://github.com/zsh-a/NaviWealth/releases/download/v0.8.50/app.apk',
        'sha256': sha,
        'size': 1234,
        'releaseNotes': <String>['Fix voice startup'],
      });

      expect(manifest, isNotNull);
      expect(manifest!.versionKey, '0.8.50+125');
      expect(manifest.sizeBytes, 1234);
      expect(manifest.releaseNotes, ['Fix voice startup']);
    });

    test('rejects non-GitHub downloads and malformed hashes', () {
      expect(
        NativeUpdateManifest.tryParse(<String, Object?>{
          'versionName': '0.8.50',
          'versionCode': 125,
          'apkUrl': 'https://example.com/app.apk',
          'sha256': sha,
        }),
        isNull,
      );
      expect(
        NativeUpdateManifest.tryParse(<String, Object?>{
          'versionName': '0.8.50',
          'versionCode': 125,
          'apkUrl': 'https://github.com/zsh-a/NaviWealth/releases/download/v0.8.50/app.apk',
          'sha256': 'not-a-sha256',
        }),
        isNull,
      );
    });
  });

  group('NativeUpdateNotificationController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('deduplicates notifications by release version', () async {
      final preferences = await SharedPreferences.getInstance();
      final service = _RecordingNotificationService();
      const controller = NativeUpdateNotificationController();

      expect(
        await controller.showIfNeeded(
          state: _availableState('0.8.53', 1525),
          service: service,
          preferences: preferences,
          title: 'Update available',
          body: '0.8.53',
        ),
        isTrue,
      );
      expect(service.showCount, 1);

      expect(
        await controller.showIfNeeded(
          state: _availableState('0.8.53', 1525),
          service: service,
          preferences: preferences,
          title: 'Update available',
          body: '0.8.53',
        ),
        isFalse,
      );
      expect(service.showCount, 1);

      expect(
        await controller.showIfNeeded(
          state: _availableState('0.8.54', 1526),
          service: service,
          preferences: preferences,
          title: 'Update available',
          body: '0.8.54',
        ),
        isTrue,
      );
      expect(service.showCount, 2);
    });

    test('clears the OS notification when no update should be shown', () async {
      final preferences = await SharedPreferences.getInstance();
      final service = _RecordingNotificationService();

      final shown = await const NativeUpdateNotificationController()
          .showIfNeeded(
            state: NativeUpdateState.hidden,
            service: service,
            preferences: preferences,
            title: 'Update available',
            body: '0.8.53',
          );

      expect(shown, isFalse);
      expect(service.cancelCount, 1);
    });
  });

  test('registers a twelve-hour Android update background task', () {
    final task = backgroundTaskSpecForName(kNativeUpdateTaskName);

    expect(task, same(kNativeUpdateBackgroundTask));
    expect(task?.defaultInterval, const Duration(hours: 12));
  });

  test('force refresh bypasses the cached manifest for manual checks', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final adapter = _ManifestAdapter([
      _manifestJson('0.8.52', 1524),
      _manifestJson('0.8.53', 1525),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = GitHubNativeUpdateClient(dio: dio);
    const url =
        'https://github.com/zsh-a/NaviWealth/releases/latest/download/latest.json';

    final first = await client.fetchLatestResult(
      manifestUrl: url,
      preferences: preferences,
    );
    final cached = await client.fetchLatestResult(
      manifestUrl: url,
      preferences: preferences,
    );
    final forced = await client.fetchLatestResult(
      manifestUrl: url,
      preferences: preferences,
      forceRefresh: true,
    );

    expect(first.manifest?.versionName, '0.8.52');
    expect(cached.fromCache, isTrue);
    expect(adapter.calls, 2);
    expect(forced.manifest?.versionName, '0.8.53');
    client.dispose();
  });
}

Map<String, Object?> _manifestJson(
  String versionName,
  int versionCode,
) => <String, Object?>{
  'versionName': versionName,
  'versionCode': versionCode,
  'apkUrl':
      'https://github.com/zsh-a/NaviWealth/releases/download/'
      'v$versionName/app-release.apk',
  'sha256': '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
};

class _ManifestAdapter implements HttpClientAdapter {
  _ManifestAdapter(this.payloads);

  final List<Map<String, Object?>> payloads;
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final payload = payloads[calls++];
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: <String, List<String>>{
        'content-type': <String>['application/json'],
      },
    );
  }
}

NativeUpdateState _availableState(String versionName, int versionCode) {
  return NativeUpdateState(
    currentVersion: '0.8.52',
    currentBuildNumber: '1524',
    manifest: NativeUpdateManifest(
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: Uri.parse(
        'https://github.com/zsh-a/NaviWealth/releases/download/'
        'v$versionName/app-release.apk',
      ),
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      mandatory: false,
      releaseNotes: const <String>[],
    ),
    requiredUpdate: false,
    shouldShow: true,
  );
}

class _RecordingNotificationService implements NotificationService {
  int showCount = 0;
  int cancelCount = 0;

  @override
  Stream<String> get payloads => const Stream<String>.empty();

  @override
  Future<String?> initialPayload() async => null;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required NotificationChannelSpec channel,
    String? payload,
  }) async {
    showCount++;
  }

  @override
  Future<void> cancel(int id) async {
    cancelCount++;
  }
}
