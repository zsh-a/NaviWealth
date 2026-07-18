import 'dart:async';
import 'dart:math';

import 'package:naviwealth/core/sync/hlc.dart';
import '../logging/app_logger.dart';
import 'clock.dart';
import 'cursor_store.dart';
import 'domain_generation.dart';
import 'errors.dart';
import 'op_outbox.dart';
import 'retry.dart';
import 'row_applier.dart';
import 'sync_api_client.dart';
import 'sync_stability.dart';
import 'sync_status.dart';
import 'sync_table_registry.dart';

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

/// Coordinates the row-state sync cycle (`docs/sync/sync-v3.md`).
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
    DomainGenerationStore? generationStore,
    DomainResetHandler? resetHandler,
    SyncStabilityRecorder? stabilityRecorder,
  }) : _clock = clock,
       _backoff = backoff,
       _random = random ?? Random(),
       _logger = logger ?? AppLogger.instance,
       _generationStore = generationStore ?? InMemoryDomainGenerationStore(),
       _resetHandler = resetHandler ?? const NoopDomainResetHandler(),
       _stabilityRecorder = stabilityRecorder;

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
  final DomainGenerationStore _generationStore;
  final DomainResetHandler _resetHandler;
  final SyncStabilityRecorder? _stabilityRecorder;

  EngineState _state = EngineState.idle;
  EngineState get state => _state;

  Future<SyncCycleResult>? _inflight;
  int _consecutiveFailures = 0;
  Duration? _nextBackoff;
  Duration? get nextBackoff => _nextBackoff;
  DateTime? _lastSuccessAt;
  int _cycleGenerationResets = 0;
  int _cycleGenerationResetFailures = 0;

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
    final operation = _logger.startOperation('core.sync.cycle');
    final errors = <SyncException>[];
    var pushed = 0;
    var pulled = 0;
    var conflicts = const SyncConflictDiagnostics.empty();
    _cycleGenerationResets = 0;
    _cycleGenerationResetFailures = 0;
    _state = EngineState.syncing;
    _emitStatus(
      SyncStatus.syncing,
      conflicts: const SyncConflictDiagnostics.empty(),
    );

    try {
      var since = await operation.step('read_cursor', cursors.readSeq);
      while (true) {
        final generations = await operation.step(
          'read_domain_generations',
          _generationStore.readAll,
        );
        final batch = await operation.step(
          'collect_batch',
          () => _collectBatch(generations),
          fields: {'batch_size': kSyncMaxChanges},
        );
        final SyncResponse resp;
        try {
          resp = await operation.step(
            'api_sync',
            () => api.sync(
              deviceId: deviceId,
              since: since,
              changes: batch.changes,
            ),
            fields: {'batch_size': batch.changes.length},
          );
        } on SyncException catch (e) {
          errors.add(e);
          break;
        }

        pushed += resp.accepted.length;
        await operation.step(
          'reconcile_domain_generations',
          () => _reconcileDomainGenerations(resp.domainGenerations),
        );
        final currentRows = resp.changes
            .where((row) {
              final domain = domainWireForWireTable(row.table);
              if (domain == null) return false;
              return row.generation == (resp.domainGenerations[domain] ?? 0);
            })
            .toList(growable: false);
        if (currentRows.isNotEmpty) {
          final report = await operation.step(
            'apply_rows',
            () => applier.applyWithReport(currentRows),
            fields: {'row_count': currentRows.length},
          );
          pulled += report.written;
          conflicts = conflicts.merge(_conflictsFromApplyReport(report));
          await _mergeHighest(currentRows);
        }
        // Acknowledge only rows the server explicitly accepted. Rows dropped
        // at the domain-claim boundary stay dirty so the user can fix their
        // opt-in/token state and retry instead of losing local edits.
        await operation.step(
          'clear_acknowledged',
          () => pending.clear(batch.acknowledgedOpIds(resp.acceptedKeys)),
        );
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
      operation.complete(
        fields: {'pushed_count': pushed, 'pulled_count': pulled},
      );
      _emitStatus(SyncStatus.online, conflicts: conflicts);
      return _recordStability(
        SyncCycleResult(
          pushed: pushed,
          pulled: pulled,
          errors: const [],
          conflicts: conflicts,
        ),
      );
    }
    operation.fail(
      errors.first,
      stage: 'cycle',
      errorCode: 'sync_${errors.first.kind.name}',
      retryable: errors.first.isRetryable,
      fields: {
        'pushed_count': pushed,
        'pulled_count': pulled,
        'error_count': errors.length,
      },
    );
    return _recordStability(
      _handleErrors(
        errors,
        pushed: pushed,
        pulled: pulled,
        conflicts: conflicts,
      ),
    );
  }

  Future<SyncCycleResult> _recordStability(SyncCycleResult result) async {
    try {
      await _stabilityRecorder?.record(
        SyncStabilitySample(
          at: _clock.now(),
          success: result.success,
          retryableFailures: result.errors
              .where((error) => error.isRetryable)
              .length,
          fatalFailures: result.errors
              .where((error) => !error.isRetryable)
              .length,
          localWins: result.conflicts.localWins,
          ignoredRows: result.conflicts.ignoredRows,
          generationResets: _cycleGenerationResets,
          generationResetFailures: _cycleGenerationResetFailures,
        ),
      );
    } on Object catch (error) {
      // Diagnostics must never turn an otherwise valid sync outcome into a
      // failed cycle or hide the original protocol result from the caller.
      _logger.w('sync: failed to persist stability sample ($error)');
    }
    return result;
  }

  /// Read the dirty-row set, dedupe to one [RowChange] per row, and cap the
  /// batch at [kSyncMaxChanges].
  Future<_Batch> _collectBatch(Map<String, int> generations) async {
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
      final change = _toRowChange(
        pointer.table,
        pointer.rowId,
        data,
        generations,
      );
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

  RowChange _toRowChange(
    String table,
    String id,
    Map<String, Object?> data,
    Map<String, int> generations,
  ) {
    final version = (data['hlc'] as String?) ?? Hlc.zero(deviceId).toString();
    // D-1.4: tag every outgoing row with its LifeOS domain prefix. The prefix
    // is dispatched per table ([domainPrefixForTable]): FinanceOS rows ride
    // `fin:`, HealthOS rows ride `health:`, KnowledgeOS rows ride `know:`,
    // and ExecutionOS rows ride `exec:`.
    return RowChange(
      table: prefixTable(table),
      id: id,
      payload: data,
      version: version,
      deleted: data['deleted_at'] != null,
      generation: generations[domainWireForLocalTable(table)] ?? 0,
    );
  }

  Future<void> _reconcileDomainGenerations(
    Map<String, int> serverGenerations,
  ) async {
    final local = await _generationStore.readAll();
    for (final entry in serverGenerations.entries) {
      final current = local[entry.key] ?? 0;
      if (current != entry.value) {
        try {
          await _resetHandler.resetLocalDomain(entry.key);
          _cycleGenerationResets++;
        } on Object {
          _cycleGenerationResetFailures++;
          rethrow;
        }
      }
      await _generationStore.write(entry.key, entry.value);
    }
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
