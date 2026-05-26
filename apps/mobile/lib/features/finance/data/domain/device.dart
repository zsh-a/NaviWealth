import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import 'enums.dart';

part 'device.freezed.dart';

/// Trusted device record. Generated locally on first launch and persisted
/// in encrypted storage; the `id` is also used as the HLC `nodeId` so any
/// row this device writes is traceable back to a known device.
@freezed
abstract class Device with _$Device {
  const factory Device({
    required String id,
    required String name,
    required DevicePlatform platform,
    String? appVersion,
    DateTime? lastSyncAt,
    Hlc? lastHlc,
    required SyncMeta sync,
  }) = _Device;
}
