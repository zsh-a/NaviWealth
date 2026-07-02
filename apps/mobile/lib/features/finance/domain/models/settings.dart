import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import 'enums.dart';

part 'settings.freezed.dart';

@freezed
abstract class Settings with _$Settings {
  const factory Settings({
    required String userId,
    required String baseCurrency,
    required AppThemeMode themeMode,
    required PrivacyMode privacyMode,
    required CostBasisMethod costBasisMethod,
    required SyncMeta sync,
  }) = _Settings;
}
