import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'sync_meta.dart';

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
