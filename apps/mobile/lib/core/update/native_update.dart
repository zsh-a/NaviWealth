import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../design_system/preferences/theme_preferences.dart';
import '../config/providers.dart';

const String kNativeUpdateDismissedVersionKey =
    'naviwealth.update.native.dismissed_version';

final packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

final nativeUpdateStateProvider = FutureProvider<NativeUpdateState>((
  ref,
) async {
  final config = ref.watch(appConfigProvider);
  if (!_isMobileNativePlatform || !config.hasNativeUpdateTarget) {
    return NativeUpdateState.hidden;
  }

  final packageInfo = await ref.watch(packageInfoProvider.future);
  final latest = config.latestNativeVersion.trim();
  final updateUrl = config.nativeUpdateUrl.trim();
  final uri = Uri.tryParse(updateUrl);
  final hasLaunchableUrl = uri != null && uri.hasScheme;
  if (!hasLaunchableUrl ||
      !isNativeUpdateNewer(latest, packageInfo.version.trim())) {
    return NativeUpdateState.hidden;
  }

  final prefs = ref.watch(sharedPreferencesProvider);
  final dismissed =
      prefs.getString(kNativeUpdateDismissedVersionKey) == latest &&
      !config.nativeUpdateRequired;

  return NativeUpdateState(
    currentVersion: packageInfo.version.trim(),
    latestVersion: latest,
    updateUrl: updateUrl,
    requiredUpdate: config.nativeUpdateRequired,
    shouldShow: !dismissed,
  );
});

bool get _isMobileNativePlatform {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

class NativeUpdateState {
  const NativeUpdateState({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.requiredUpdate,
    required this.shouldShow,
  });

  static const hidden = NativeUpdateState(
    currentVersion: '',
    latestVersion: '',
    updateUrl: '',
    requiredUpdate: false,
    shouldShow: false,
  );

  final String currentVersion;
  final String latestVersion;
  final String updateUrl;
  final bool requiredUpdate;
  final bool shouldShow;
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
