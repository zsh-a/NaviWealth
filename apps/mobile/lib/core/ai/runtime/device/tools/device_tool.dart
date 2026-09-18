/// Device tool contract.
///
/// The device equivalent of one historical backend tool entry.
/// Schema + description are ported **verbatim** from the backend so the
/// model sees the stabilized tool surface on device.
/// The implementation, however, reads **Drift** (local source of
/// truth) instead of D1 read models — so there is no freshness gate on
/// this path (§4.6.1 / §11).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../device_tool_session.dart';

/// What a [DeviceTool.invoke] gets: Riverpod access for the
/// repositories/services it reuses, plus the live turn session (for
/// the device-derived portfolio snapshot, mirroring the backend
/// `ToolCtx`).
class DeviceToolContext {
  DeviceToolContext({required this.ref, required this.session});

  /// Read device providers/services here — never cache across turns;
  /// the dispatcher creates a fresh context per call.
  final Ref ref;
  final DeviceToolSession session;
  final _subscriptions = <ProviderSubscription<Object?>>[];
  final _pendingReads = <void Function()>{};
  bool _disposed = false;

  /// Await a settled read-model projection, including nullable/empty data.
  /// Loading (including refresh with stale data) is not "unavailable".
  /// The dispatcher's existing timeout remains the single time budget.
  Future<T> readAsync<T>(ProviderListenable<AsyncValue<T>> provider) async {
    if (_disposed) throw StateError('tool_context_disposed');
    final result = Completer<T>();
    final subscription = ref.container.listen(
      provider,
      (_, value) {
        if (result.isCompleted || value.isLoading) return;
        if (value.hasError) {
          result.completeError(
            value.error!,
            value.stackTrace ?? StackTrace.current,
          );
        } else if (value.hasValue) {
          result.complete(value.requireValue);
        }
      },
      fireImmediately: true,
      onError: (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    void cancel() {
      if (!result.isCompleted) {
        result.completeError(StateError('tool_context_disposed'));
      }
    }

    _subscriptions.add(subscription);
    _pendingReads.add(cancel);
    try {
      return await result.future;
    } finally {
      _pendingReads.remove(cancel);
      _subscriptions.remove(subscription);
      subscription.close();
    }
  }

  /// Hold auto-dispose providers through a cold one-shot read. The dispatcher
  /// also closes outstanding subscriptions when a tool times out.
  Future<T> readFuture<T>(ProviderListenable<Future<T>> provider) async {
    if (_disposed) throw StateError('tool_context_disposed');
    // A provider-owned listener can be paused when the initiating UI leaves.
    // A scoped container subscription keeps this operation (only) alive.
    final subscription = ref.container.listen(provider, (_, _) {});
    _subscriptions.add(subscription);
    try {
      return await subscription.read();
    } finally {
      _subscriptions.remove(subscription);
      subscription.close();
    }
  }

  void dispose() {
    _disposed = true;
    for (final cancel in _pendingReads.toList()) {
      cancel();
    }
    _pendingReads.clear();
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
  }
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
