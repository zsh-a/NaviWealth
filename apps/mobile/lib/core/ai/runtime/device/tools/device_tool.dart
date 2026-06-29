/// Device tool contract.
///
/// The device equivalent of one historical backend tool entry.
/// Schema + description are ported **verbatim** from the backend so the
/// model sees the stabilized tool surface on device.
/// The implementation, however, reads **Drift** (local source of
/// truth) instead of D1 read models — so there is no freshness gate on
/// this path (§4.6.1 / §11).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device_tool_session.dart';

/// What a [DeviceTool.invoke] gets: Riverpod access for the
/// repositories/services it reuses, plus the live turn session (for
/// the device-derived portfolio snapshot, mirroring the backend
/// `ToolCtx`).
class DeviceToolContext {
  const DeviceToolContext({required this.ref, required this.session});

  /// Read device providers/services here — never cache across turns;
  /// the dispatcher creates a fresh context per call.
  final Ref ref;
  final DeviceToolSession session;
}

abstract class DeviceTool {
  /// Wire name — must equal the backend tool name.
  String get name;

  /// Description shown to the model (ported verbatim from the backend
  /// `DESCRIPTION`).
  String get description;

  /// JSON Schema for the tool input (ported verbatim).
  Map<String, Object?> get inputSchema;

  /// Execute against local data. Returns the JSON-able value the loop
  /// serialises into a `tool_result`. Should surface failures as an
  /// `{error, code}` map rather than throwing where it can; the
  /// dispatcher converts uncaught throws into a standard error shape.
  Future<Object?> invoke(DeviceToolContext ctx, Map<String, Object?> input);
}
