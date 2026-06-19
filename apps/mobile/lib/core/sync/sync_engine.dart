import 'dart:async';
import 'dart:math';

import 'package:naviwealth/core/sync/hlc.dart';
import '../logging/app_logger.dart';
import 'clock.dart';
import 'cursor_store.dart';
import 'domain_prefix.dart';
import 'errors.dart';
import 'op_outbox.dart';
import 'retry.dart';
import 'row_applier.dart';
import 'sync_api_client.dart';
import 'sync_status.dart';

/// SyncEngine state — exposed for tests and status display.
enum EngineState { idle, syncing, backoff, halted }

/// Outcome of one sync cycle.
class SyncCycleResult {
  const SyncCycleResult({
    required this.pushed,
    required this.pulled,
    required this.errors,
    this.conflicts = const SyncConflictDiagnostics.empty(),
  });
  final int pushed;
  final int pulled;
  final List<SyncException> errors;
  final SyncConflictDiagnostics conflicts;

  bool get success => errors.isEmpty;
}

/// Coordinates the row-state sync cycle (`docs/sync-v2.md` §7.3).
///
/// One cycle drains both directions: it reads the dirty-row set, pushes each
/// row's current state and pulls peers' newer rows in a single `POST /sync`,
/// loops while either side still has a backlog, and applies remote rows with
/// per-row LWW.
///
/// Invariants:
///  - At most one [run] in flight; concurrent callers share the future.
///  - A failed push never blocks the pull — both ride the same request, and
///    a row that won't push just stays dirty without holding up other rows.
///  - Backoff resets on any successful cycle.
class SyncEngine {
  SyncEngine({
    required this.api,
    required this.pending,
    required this.cursors,
    required this.applier,
    required this.deviceId,
    required this.statusBus,
    Clock clock = const SystemClock(),
    BackoffPolicy backoff = const BackoffPolicy(),
    Random? random,
    AppLogger? logger,
  }) : _clock = clock,
       _backoff = backoff,
       _random = random ?? Random(),
       _logger = logger ?? AppLogger.instance;

  final SyncApiClient api;
  final PendingRows pending;
  final CursorStore cursors;
  final RowApplier applier;
  final String deviceId;
  final SyncStatusBus statusBus;
  final Clock _clock;
  final BackoffPolicy _backoff;
  final Random _random;
  final AppLogger _logger;

  EngineState _state = EngineState.idle;
  EngineState get state => _state;

  Future<SyncCycleResult>? _inflight;
  int _consecutiveFailures = 0;
  Duration? _nextBackoff;
  Duration? get nextBackoff => _nextBackoff;
  DateTime? _lastSuccessAt;

  Future<Hlc> _loadLocalHlc() async {
    final hlc = await cursors.readLocalHlc();
    return hlc ?? Hlc.zero(deviceId);
  }

  /// Stamp a fresh HLC for a locally-authored write. This is the row's LWW
  /// version token; the mutation write path depends on it.
  Future<Hlc> stampHlc({int? overrideNowMillis}) async {
    final last = await _loadLocalHlc();
    final next = Hlc.tick(
      lastSeen: last,
      nowMillis: overrideNowMillis ?? _clock.nowMillis(),
    );
    await cursors.writeLocalHlc(next);
    return next;
  }

  /// Keep the local clock ahead of any version observed from a peer, so a
  /// subsequent local edit of a pulled row reliably wins LWW.
  Future<void> _mergeRemote(Hlc remote) async {
    final last = await _loadLocalHlc();
    final merged = last.merge(remote, nowMillis: _clock.nowMillis());
    await cursors.writeLocalHlc(merged);
  }

  /// Run one sync cycle. Concurrent callers share the in-flight future.
  Future<SyncCycleResult> run() {
    return _inflight ??= _runOnce().whenComplete(() => _inflight = null);
  }

  Future<SyncCycleResult> _runOnce() async {
    final errors = <SyncException>[];
    var pushed = 0;
    var pulled = 0;
    var conflicts = const SyncConflictDiagnostics.empty();
    _state = EngineState.syncing;
    _emitStatus(
      SyncStatus.syncing,
      conflicts: const SyncConflictDiagnostics.empty(),
    );

    try {
      var since = await cursors.readSeq();
      while (true) {
        final batch = await _collectBatch();
        final SyncResponse resp;
        try {
          resp = await api.sync(
            deviceId: deviceId,
            since: since,
            changes: batch.changes,
          );
        } on SyncException catch (e) {
          errors.add(e);
          break;
        }

        pushed += resp.accepted.length;
        if (resp.changes.isNotEmpty) {
          final report = await applier.applyWithReport(resp.changes);
          pulled += report.written;
          conflicts = conflicts.merge(_conflictsFromApplyReport(report));
          await _mergeHighest(resp.changes);
        }
        // Acknowledge only rows the server explicitly accepted. Rows dropped
        // at the domain-claim boundary stay dirty so the user can fix their
        // opt-in/token state and retry instead of losing local edits.
        await pending.clear(batch.acknowledgedOpIds(resp.acceptedKeys));
        since = resp.seq;
        await cursors.writeSeq(since);

        if (!batch.morePending && !resp.more) break;
      }
    } catch (e) {
      errors.add(
        e is SyncException
            ? e
            : SyncException(SyncErrorKind.unknown, message: '$e', cause: e),
      );
    }

    if (errors.isEmpty) {
      _consecutiveFailures = 0;
      _nextBackoff = null;
      _state = EngineState.idle;
      _lastSuccessAt = _clock.now();
      _logger.d('sync: cycle complete (pushed=$pushed, pulled=$pulled)');
      _emitStatus(SyncStatus.online, conflicts: conflicts);
      return SyncCycleResult(
        pushed: pushed,
        pulled: pulled,
        errors: const [],
        conflicts: conflicts,
      );
    }
    return _handleErrors(
      errors,
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
    );
  }

  /// Read the dirty-row set, dedupe to one [RowChange] per row, and cap the
  /// batch at [kSyncMaxChanges].
  Future<_Batch> _collectBatch() async {
    final pointers = await pending.pointers();
    final order = <String>[];
    final opIdsByKey = <String, List<String>>{};
    final keyToPointer = <String, PendingPointer>{};
    for (final p in pointers) {
      final key = '${p.table}\u{0}${p.rowId}';
      if (!opIdsByKey.containsKey(key)) {
        order.add(key);
        keyToPointer[key] = p;
      }
      opIdsByKey.putIfAbsent(key, () => <String>[]).add(p.opId);
    }

    final take = order.length > kSyncMaxChanges
        ? kSyncMaxChanges
        : order.length;
    final changes = <RowChange>[];
    final staleOpIds = <String>[];
    final opIdsByWireKey = <String, List<String>>{};
    for (var i = 0; i < take; i++) {
      final key = order[i];
      final pointer = keyToPointer[key]!;
      final data = await pending.readRow(pointer.table, pointer.rowId);
      final opIds = opIdsByKey[key]!;
      if (data == null) {
        staleOpIds.addAll(opIds);
        continue;
      }
      final change = _toRowChange(pointer.table, pointer.rowId, data);
      changes.add(change);
      opIdsByWireKey[_rowKey(change.table, change.id)] = opIds;
    }
    return _Batch(
      changes: changes,
      staleOpIds: staleOpIds,
      opIdsByWireKey: opIdsByWireKey,
      morePending: order.length > take,
    );
  }

  RowChange _toRowChange(String table, String id, Map<String, Object?> data) {
    final version = (data['hlc'] as String?) ?? Hlc.zero(deviceId).toString();
    // D-1.4: tag every outgoing row with its LifeOS domain prefix. The prefix
    // is dispatched per table ([domainPrefixForTable]): FinanceOS rows ride
    // `fin:`, HealthOS rows ride `health:`, and KnowledgeOS rows ride `know:`.
    return RowChange(
      table: prefixTable(table),
      id: id,
      payload: data,
      version: version,
      deleted: data['deleted_at'] != null,
    );
  }

  Future<void> _mergeHighest(List<RowChange> rows) async {
    Hlc? highest;
    for (final r in rows) {
      final h = Hlc.parse(r.version);
      if (highest == null || h > highest) highest = h;
    }
    if (highest != null) await _mergeRemote(highest);
  }

  SyncCycleResult _handleErrors(
    List<SyncException> errors, {
    required int pushed,
    required int pulled,
    required SyncConflictDiagnostics conflicts,
  }) {
    final fatal = errors.where((e) => !e.isRetryable).toList();
    if (fatal.isNotEmpty) {
      _state = EngineState.halted;
      _logger.e('sync: engine halted', error: fatal.first);
      _emitStatus(
        SyncStatus.failed,
        lastError: fatal.first.toString(),
        conflicts: conflicts,
      );
      return SyncCycleResult(
        pushed: pushed,
        pulled: pulled,
        errors: errors,
        conflicts: conflicts,
      );
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
    _logger.w(
      'sync: backing off ${delay.inSeconds}s after $_consecutiveFailures failures',
      error: errors.first,
    );
    _emitStatus(
      SyncStatus.offline,
      lastError: errors.first.toString(),
      conflicts: conflicts,
    );
    return SyncCycleResult(
      pushed: pushed,
      pulled: pulled,
      errors: errors,
      conflicts: conflicts,
    );
  }

  void _emitStatus(
    SyncStatus status, {
    String? lastError,
    SyncConflictDiagnostics? conflicts,
  }) {
    statusBus.emit(
      SyncStatusEvent(
        status: status,
        at: _clock.now(),
        lastError: lastError,
        lastSuccessAt: _lastSuccessAt,
        conflicts: conflicts ?? statusBus.current.conflicts,
      ),
    );
  }

  SyncConflictDiagnostics _conflictsFromApplyReport(RowApplyReport report) {
    return SyncConflictDiagnostics(
      remoteRows: report.attempted,
      appliedRows: report.written,
      localWins: report.skippedLocalWins,
      ignoredRows: report.skippedIgnored,
    );
  }
}

class _Batch {
  const _Batch({
    required this.changes,
    required this.staleOpIds,
    required this.opIdsByWireKey,
    required this.morePending,
  });
  final List<RowChange> changes;
  final List<String> staleOpIds;
  final Map<String, List<String>> opIdsByWireKey;
  final bool morePending;

  List<String> acknowledgedOpIds(Set<String> acceptedKeys) {
    return <String>[
      ...staleOpIds,
      for (final key in acceptedKeys) ...?opIdsByWireKey[key],
    ];
  }
}

String _rowKey(String table, String id) => '$table\u{0}$id';
