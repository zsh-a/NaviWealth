import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'hlc.dart';
import 'sync_meta.dart';

part 'device.freezed.dart';

/// Trusted device record. Generated locally on first launch and persisted
/// in encrypted storage; the `id` is also used as the HLC `nodeId` so any
/// row this device writes is traceable back to a known device.
@freezed
class Device with _$Device {
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
