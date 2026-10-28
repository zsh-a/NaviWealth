import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../domain/bcr_knowledge_connection.dart';
import '../domain/bcr_knowledge_source.dart';
import 'bcr_github_client.dart';
import 'bcr_github_credentials.dart';
import 'bcr_knowledge_repository.dart';

enum BcrSyncLocalFailure implements Exception { credentials, cancelled }

class BcrSyncStatus {
  const BcrSyncStatus({
    this.syncing = false,
    this.error,
    this.retryAt,
    this.retryable = false,
  });
  final bool syncing;
  final Object? error;
  final DateTime? retryAt;
  final bool retryable;
}

/// One owner and immutable credentials per operation. This reads BCR's Git
/// snapshots; Navi's row-state sync never acquires ownership of their content.
class BcrKnowledgeSyncService {
  BcrKnowledgeSyncService({
    required this.owner,
    required this.repository,
    required this.credentials,
    required this.client,
    required this.currentOwner,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final String owner;
  final BcrKnowledgeRepository repository;
  final BcrGithubCredentials credentials;
  final BcrGithubClient client;
  final Future<String> Function() currentOwner;
  final DateTime Function() now;
  final _changes = StreamController<Map<String, BcrSyncStatus>>.broadcast();
  final _statuses = <String, BcrSyncStatus>{};
  final _running = <String, Future<void>>{};
  final _requests = <String, CancelToken>{};
  final _failures = <String, int>{};
  bool _disposed = false;
  int _batchEpoch = 0;

  Stream<Map<String, BcrSyncStatus>> get statuses => Stream.multi((controller) {
    final subscription = _changes.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.add(Map.unmodifiable(_statuses));
    controller.onCancel = subscription.cancel;
  });

  Future<void> _checkOwner(CancelToken cancel) async {
    if (_disposed || cancel.isCancelled) throw BcrSyncLocalFailure.cancelled;
    final activeOwner = await currentOwner();
    if (_disposed || cancel.isCancelled || activeOwner != owner) {
      throw BcrSyncLocalFailure.cancelled;
    }
  }

  Future<void> connect({
    required String label,
    required String repositoryAddress,
    required String branch,
    required Uri libraryUrl,
    required String token,
    CancelToken? cancelToken,
  }) async {
    if (label.trim().isEmpty || label.length > 200 || token.trim().isEmpty) {
      throw const FormatException('Invalid BCR connection');
    }
    normalizeBcrLibraryUrl(libraryUrl.toString());
    final cancel = cancelToken ?? CancelToken();
    final epoch = _batchEpoch;
    await _checkOwner(cancel);
    final lease = await repository.beginConnection(owner);
    if (epoch != _batchEpoch) cancel.cancel();
    _requests[lease.id] = cancel;
    final credentialId = const Uuid().v4();
    var stored = false;
    var committed = false;
    try {
      await _checkOwner(cancel);
      final remote = await client.read(
        repository: repositoryAddress,
        token: token,
        branch: branch,
        cancelToken: cancel,
      );
      await _checkOwner(cancel);
      _requests[remote.target.sourceId]?.cancel();
      await credentials.write(owner, credentialId, token);
      stored = true;
      await _checkOwner(cancel);
      final previous = await repository.commitConnection(
        owner: owner,
        lease: lease,
        label: label,
        libraryUrl: libraryUrl,
        credentialId: credentialId,
        remote: remote,
      );
      committed = true;
      _publish(remote.target.sourceId, const BcrSyncStatus());
      _failures.remove(remote.target.sourceId);
      if (previous != null) {
        // The new connection is already authoritative. A failed deletion cannot
        // undo it or make its old credential reachable through metadata again.
        await credentials
            .delete(owner, previous.credentialId)
            .catchError((Object _) {});
      }
    } finally {
      _requests.remove(lease.id);
      await Future.wait<void>([
        repository.cancelSyncLease(owner, lease),
        if (stored && !committed) credentials.delete(owner, credentialId),
      ]);
    }
  }

  Future<void> sync(BcrKnowledgeConnection connection, {bool manual = false}) {
    final active = _running[connection.id];
    if (active != null) return active;
    if (_disposed) return Future.error(BcrSyncLocalFailure.cancelled);
    final status = _statuses[connection.id];
    if (status?.retryAt?.isAfter(now()) == true) return Future.value();
    if (!manual && status?.error != null && status?.retryable != true) {
      return Future.value();
    }
    final operation = _sync(connection);
    _running[connection.id] = operation;
    // Install cleanup without introducing an unhandled derived failure Future.
    unawaited(
      operation.then(
        (_) {
          _running.remove(connection.id);
        },
        onError: (Object _, StackTrace _) {
          _running.remove(connection.id);
        },
      ),
    );
    return operation;
  }

  Future<void> _sync(BcrKnowledgeConnection connection) async {
    final cancel = CancelToken();
    _requests[connection.id] = cancel;
    BcrSyncLease? lease;
    _publish(connection.id, const BcrSyncStatus(syncing: true));
    try {
      await _checkOwner(cancel);
      lease = await repository.beginRemoteSync(owner, connection);
      final token = await credentials.read(owner, connection.credentialId);
      if (token == null) throw BcrSyncLocalFailure.credentials;
      await _checkOwner(cancel);
      final remote = await client.read(
        repository:
            '${connection.target.owner}/${connection.target.repository}',
        token: token,
        branch: connection.target.branch,
        knownHead: connection.remoteHead,
        hasCachedSnapshot: lease.cacheRevision != null,
        cancelToken: cancel,
      );
      await _checkOwner(cancel);
      await repository.commitRemoteSync(
        owner: owner,
        lease: lease,
        connection: connection,
        remote: remote,
      );
      _failures.remove(connection.id);
      _publish(connection.id, const BcrSyncStatus());
    } on Object catch (error) {
      final current = await repository.findConnection(owner, connection.id);
      if (current?.revision == connection.revision) {
        if (error == BcrSyncLocalFailure.cancelled ||
            error == BcrKnowledgeCacheFailure.changed ||
            (error is DioException && CancelToken.isCancel(error))) {
          _publish(connection.id, const BcrSyncStatus());
        } else {
          final retryable =
              error is BcrGithubFailure &&
              (error.code == BcrGithubFailureCode.network ||
                  error.code == BcrGithubFailureCode.rateLimited);
          final count = _failures.update(
            connection.id,
            (count) => count + 1,
            ifAbsent: () => 0,
          );
          var delay = Duration(
            milliseconds: (10000 << count.clamp(0, 5)).clamp(10000, 300000),
          );
          if (error is BcrGithubFailure &&
              error.retryAfter != null &&
              error.retryAfter! > delay) {
            delay = error.retryAfter!;
          }
          _publish(
            connection.id,
            BcrSyncStatus(
              error: error,
              retryable: retryable,
              retryAt: retryable ? now().add(delay) : null,
            ),
          );
        }
      }
      rethrow;
    } finally {
      _requests.remove(connection.id);
      if (lease != null) await repository.cancelSyncLease(owner, lease);
    }
  }

  Future<void> syncAll({bool manual = false}) async {
    if (_disposed) return;
    final epoch = _batchEpoch;
    for (final connection in await repository.listConnections(owner)) {
      if (_disposed || epoch != _batchEpoch) return;
      try {
        await sync(connection, manual: manual);
      } on Object {
        /* Status retains the error. */
      }
    }
  }

  Future<void> disconnect(BcrKnowledgeConnection connection) async {
    _requests[connection.id]?.cancel();
    await repository.disconnect(owner, connection);
    await credentials.delete(owner, connection.credentialId);
    _publish(connection.id, const BcrSyncStatus());
  }

  void cancelAll() {
    _batchEpoch++;
    for (final request in _requests.values) {
      request.cancel();
    }
  }

  void cancelSource(String id) => _requests[id]?.cancel();

  void _publish(String id, BcrSyncStatus status) {
    if (_disposed) return;
    _statuses[id] = status;
    _changes.add(Map.unmodifiable(_statuses));
  }

  void dispose() {
    _disposed = true;
    cancelAll();
    unawaited(_changes.close());
  }
}
