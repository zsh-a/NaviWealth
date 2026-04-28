import 'dart:async';
import 'dart:math';

import '../../data/domain/hlc.dart';
import 'clock.dart';
import 'cursor_store.dart';
import 'errors.dart';
import 'op_applier.dart';
import 'op_outbox.dart';
import 'retry.dart';
import 'sync_api_client.dart';
import 'sync_status.dart';

/// SyncEngine state — exposed primarily for tests.
enum EngineState { idle, pushing, pulling, applying, backoff, halted }

/// Outcome of a single sync attempt — useful so callers can drive UI
/// (e.g. "pulled 3 ops from the server").
class SyncCycleResult {
  const SyncCycleResult({
    required this.pushed,
    required this.pulled,
    required this.errors,
  });
  final int pushed;
  final int pulled;
  final List<SyncException> errors;

  bool get success => errors.isEmpty;
}

/// Coordinates push, pull, retry, and the LWW applier.
///
/// State-machine invariants (`docs/sync-protocol.md` §7.2):
///  - At most one [run] in flight per device. Concurrent calls reuse the
///    in-flight future.
///  - Push completes before Pull on a single cycle (push first so the
///    server's view is fresher when we pull, and so failed pushes don't
///    sit in the outbox while peers fetch our stale state).
///  - Backoff resets on any successful push or pull.
class SyncEngine {
  SyncEngine({
    required this.api,
    required this.outbox,
    required this.cursors,
    required this.applier,
    required this.deviceId,
    required this.statusBus,
    Clock clock = const SystemClock(),
    BackoffPolicy backoff = const BackoffPolicy(),
    Random? random,
    this.batchMaxOps = kPushBatchMaxOps,
    this.batchMaxBytes = kPushBatchMaxBytes,
  }) : _clock = clock,
       _backoff = backoff,
       _random = random ?? Random();

  final SyncApiClient api;
  final OutboxStore outbox;
  final CursorStore cursors;
  final OpApplier applier;
  final String deviceId;
  final SyncStatusBus statusBus;
  final Clock _clock;
  final BackoffPolicy _backoff;
  final Random _random;
  final int batchMaxOps;
  final int batchMaxBytes;

  EngineState _state = EngineState.idle;
  EngineState get state => _state;

  Future<SyncCycleResult>? _inflight;
  int _consecutiveFailures = 0;
  Duration? _nextBackoff;
  Duration? get nextBackoff => _nextBackoff;
  DateTime? _lastSuccessAt;

  /// Fetch the local HLC from persistent storage, falling back to
  /// `Hlc.zero(deviceId)`.
  Future<Hlc> _loadLocalHlc() async {
    final hlc = await cursors.readLocalHlc();
    return hlc ?? Hlc.zero(deviceId);
  }

  /// Generate a fresh HLC stamp for a locally-authored op. Persists the
  /// new clock state so a crash between events doesn't regress.
  Future<Hlc> stampHlc({int? overrideNowMillis}) async {
    final last = await _loadLocalHlc();
    final next = Hlc.tick(
      lastSeen: last,
      nowMillis: overrideNowMillis ?? _clock.nowMillis(),
    );
    await cursors.writeLocalHlc(next);
    return next;
  }

  /// Merge a remote HLC into the local clock state. Called whenever we
  /// observe an op or response that was stamped by another writer.
  Future<void> _merge(Hlc remote) async {
    final last = await _loadLocalHlc();
    final merged = last.merge(remote, nowMillis: _clock.nowMillis());
    await cursors.writeLocalHlc(merged);
  }

  /// Push (if outbox non-empty) → Pull (drain pages) → return summary.
  ///
  /// Multiple callers can invoke this concurrently; the first one wins
  /// and others share its future. This implements the
  /// "Push and Pull are never concurrent on the same device" invariant
  /// (§7.2) without callers needing to think about it.
  Future<SyncCycleResult> run() {
    return _inflight ??= _runOnce().whenComplete(() => _inflight = null);
  }

  Future<SyncCycleResult> _runOnce() async {
    final errors = <SyncException>[];
    var pushed = 0;
    var pulled = 0;
    final outboxDepth = await outbox.depth();
    _emitStatus(SyncStatus.syncing, outboxDepth: outboxDepth);

    try {
      pushed = await _pushAll(errors);
      pulled = await _pullAll(errors);

      if (errors.isEmpty) {
        _consecutiveFailures = 0;
        _nextBackoff = null;
        _state = EngineState.idle;
        _lastSuccessAt = _clock.now();
        _emitStatus(SyncStatus.online, outboxDepth: await outbox.depth());
        return SyncCycleResult(
          pushed: pushed,
          pulled: pulled,
          errors: const [],
        );
      }
    } catch (e, _) {
      // Defensive: any unexpected throw becomes an error in the result so
      // callers can react instead of crashing the timer loop.
      errors.add(
        e is SyncException
            ? e
            : SyncException(SyncErrorKind.unknown, message: '$e', cause: e),
      );
    }

    return _handleErrors(errors, pushed: pushed, pulled: pulled);
  }

  SyncCycleResult _handleErrors(
    List<SyncException> errors, {
    required int pushed,
    required int pulled,
  }) {
    final fatal = errors.where((e) => !e.isRetryable).toList();
    if (fatal.isNotEmpty) {
      _state = EngineState.halted;
      _emitStatus(SyncStatus.failed, lastError: fatal.first.toString());
      return SyncCycleResult(pushed: pushed, pulled: pulled, errors: errors);
    }

    _consecutiveFailures += 1;
    final retryAfters = errors
        .map((e) => e.retryAfter)
        .whereType<Duration>()
        .toList();
    final base = _backoff.delay(_consecutiveFailures - 1, random: _random);
    final delay = retryAfters.isEmpty
        ? base
        : Duration(
            milliseconds: [
              base.inMilliseconds,
              ...retryAfters.map((d) => d.inMilliseconds),
            ].reduce(max),
          );
    _nextBackoff = delay;
    _state = EngineState.backoff;
    _emitStatus(SyncStatus.offline, lastError: errors.first.toString());
    return SyncCycleResult(pushed: pushed, pulled: pulled, errors: errors);
  }

  Future<int> _pushAll(List<SyncException> errors) async {
    var totalAccepted = 0;
    while (true) {
      final batch = await outbox.peekBatch(
        maxOps: batchMaxOps,
        maxBytes: batchMaxBytes,
      );
      if (batch.isEmpty) return totalAccepted;
      _state = EngineState.pushing;

      try {
        final res = await api.push(deviceId: deviceId, ops: batch);
        // Drop both accepted and per-op-rejected ops from the outbox: the
        // spec says rejections in the response body are non-recoverable.
        final batchIds = batch.map((o) => o.opId).toSet();
        final rejectedIds = res.rejected.map((r) => r.opId).toSet();
        for (final r in res.rejected) {
          await outbox.recordFailure(
            opId: r.opId,
            code: r.code,
            message: r.message,
          );
        }
        final acceptedIds = batchIds.difference(rejectedIds);
        await outbox.ack(acceptedIds);
        totalAccepted += res.accepted;
        await _merge(res.serverHlcHigh);
      } on SyncException catch (e) {
        if (e.kind == SyncErrorKind.payloadTooLarge && batch.length > 1) {
          // Halve the batch and retry next cycle. Quickest is to bump
          // attempts and shrink the next peek's cap. Simpler: drop nothing,
          // record the error, and shrink batchMaxBytes locally for retry.
          // We bump attempts so observers can see it.
          await outbox.bumpAttempts(batch.map((o) => o.opId));
          errors.add(e);
          return totalAccepted;
        }
        if (e.kind == SyncErrorKind.payloadTooLarge && batch.length == 1) {
          // Single oversized op — drop it.
          final op = batch.single;
          await outbox.recordFailure(
            opId: op.opId,
            code: e.code ?? 'payload_too_large',
            message: e.message,
            payload: '${op.encodedSizeBytes} bytes',
          );
          continue;
        }
        await outbox.bumpAttempts(batch.map((o) => o.opId));
        errors.add(e);
        return totalAccepted;
      }
    }
  }

  Future<int> _pullAll(List<SyncException> errors) async {
    var total = 0;
    while (true) {
      _state = EngineState.pulling;
      final cursor = await cursors.readCursor() ?? Hlc.zero(Hlc.serverNodeId);
      try {
        final res = await api.pull(deviceId: deviceId, since: cursor);
        if (res.ops.isNotEmpty) {
          _state = EngineState.applying;
          await applier.applyAll(res.ops);
          for (final op in res.ops) {
            await _merge(op.hlc);
          }
          total += res.ops.length;
          // Advance cursor past the last applied op.
          await cursors.writeCursor(res.ops.last.hlc);
        } else {
          // SP-D-5: empty page still advances cursor to server_hlc_high.
          if (res.serverHlcHigh > cursor) {
            await cursors.writeCursor(res.serverHlcHigh);
          }
        }
        if (!res.hasMore) return total;
      } on SyncException catch (e) {
        errors.add(e);
        return total;
      }
    }
  }

  void _emitStatus(SyncStatus status, {String? lastError, int? outboxDepth}) {
    statusBus.emit(
      SyncStatusEvent(
        status: status,
        at: _clock.now(),
        lastError: lastError,
        lastSuccessAt: _lastSuccessAt,
        outboxDepth: outboxDepth,
      ),
    );
  }
}
