part of 'bcr_knowledge_repository.dart';

class BcrSyncLease {
  const BcrSyncLease({
    required this.id,
    required this.token,
    this.cacheRevision,
    this.connectionRevision,
    this.connections = const {},
  });
  final String id;
  final String token;
  final String? cacheRevision;
  final String? connectionRevision;
  final Map<String, String> connections;
}

extension BcrKnowledgeSyncRepository on BcrKnowledgeRepository {
  Stream<List<BcrKnowledgeConnection>> watchConnections(String owner) =>
      (_db.select(_db.knowledgeSourceConnections)
            ..where((row) => row.ownerUserId.equals(owner)))
          .watch()
          .map((rows) => rows.map(_connection).toList(growable: false));

  Future<List<BcrKnowledgeConnection>> listConnections(String owner) async =>
      (await (_db.select(
            _db.knowledgeSourceConnections,
          )..where((row) => row.ownerUserId.equals(owner))).get())
          .map(_connection)
          .toList(growable: false);

  Future<BcrKnowledgeConnection?> findConnection(
    String owner,
    String id,
  ) async {
    final row =
        await (_db.select(_db.knowledgeSourceConnections)..where(
              (row) => row.ownerUserId.equals(owner) & row.sourceId.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _connection(row);
  }

  /// Stage before HTTP, even when the remote default branch is not known yet.
  Future<BcrSyncLease> beginConnection(String owner) =>
      _db.transaction(() async {
        final connections = await listConnections(owner);
        final token = const Uuid().v4();
        final id = 'connect:$token';
        await _newLease(owner, id, token);
        return BcrSyncLease(
          id: id,
          token: token,
          connections: Map.unmodifiable({
            for (final item in connections) item.id: item.revision,
          }),
        );
      });

  Future<BcrSyncLease> beginRemoteSync(
    String owner,
    BcrKnowledgeConnection connection,
  ) => _db.transaction(() async {
    final current = await findConnection(owner, connection.id);
    if (current?.revision != connection.revision) {
      throw BcrKnowledgeCacheFailure.changed;
    }
    final cached = await findSource(owner, connection.id);
    final token = const Uuid().v4();
    await _newLease(owner, connection.id, token);
    return BcrSyncLease(
      id: connection.id,
      token: token,
      cacheRevision: cached?.cacheRevision,
      connectionRevision: connection.revision,
    );
  });

  Future<void> _newLease(String owner, String id, String token) => _db
      .into(_db.knowledgeSourceImportLeases)
      .insertOnConflictUpdate(
        KnowledgeSourceImportLeasesCompanion.insert(
          ownerUserId: owner,
          sourceId: id,
          token: token,
        ),
      );

  Future<void> cancelSyncLease(String owner, BcrSyncLease lease) async {
    await (_db.delete(_db.knowledgeSourceImportLeases)..where(
          (row) =>
              row.ownerUserId.equals(owner) &
              row.sourceId.equals(lease.id) &
              row.token.equals(lease.token),
        ))
        .go();
  }

  Future<void> _verifySyncLease(String owner, BcrSyncLease lease) async {
    final row =
        await (_db.select(_db.knowledgeSourceImportLeases)..where(
              (row) =>
                  row.ownerUserId.equals(owner) & row.sourceId.equals(lease.id),
            ))
            .getSingleOrNull();
    if (row?.token != lease.token) throw BcrKnowledgeCacheFailure.changed;
  }

  Future<BcrKnowledgeConnection?> commitConnection({
    required String owner,
    required BcrSyncLease lease,
    required String label,
    required Uri libraryUrl,
    required String credentialId,
    required BcrGithubRead remote,
  }) => _db.transaction(() async {
    await _verifySyncLease(owner, lease);
    final current = await findConnection(owner, remote.target.sourceId);
    if (current?.revision != lease.connections[remote.target.sourceId] ||
        remote.snapshot == null) {
      throw BcrKnowledgeCacheFailure.changed;
    }
    final url = normalizeBcrLibraryUrl(libraryUrl.toString());
    // Adopt any older file-import projection of the same configured page.
    await (_db.delete(_db.knowledgeSourceCache)..where(
          (row) =>
              row.ownerUserId.equals(owner) &
              row.sourceId.equals(bcrSourceId(url)),
        ))
        .go();
    await _storeRemoteSnapshot(
      owner,
      remote.target.sourceId,
      label,
      url,
      remote.snapshot!,
    );
    await _db
        .into(_db.knowledgeSourceConnections)
        .insertOnConflictUpdate(
          KnowledgeSourceConnectionsCompanion.insert(
            ownerUserId: owner,
            sourceId: remote.target.sourceId,
            label: label.trim(),
            libraryUrl: url.toString(),
            repositoryOwner: remote.target.owner,
            repositoryName: remote.target.repository,
            branch: remote.target.branch,
            revision: const Uuid().v4(),
            credentialId: credentialId,
            remoteHead: Value(remote.head),
            checkedAt: Value(DateTime.now().toUtc()),
          ),
        );
    await cancelSyncLease(owner, lease);
    return current;
  });

  Future<void> commitRemoteSync({
    required String owner,
    required BcrSyncLease lease,
    required BcrKnowledgeConnection connection,
    required BcrGithubRead remote,
  }) => _db.transaction(() async {
    await _verifySyncLease(owner, lease);
    final current = await findConnection(owner, connection.id);
    if (current?.revision != lease.connectionRevision ||
        remote.target.sourceId != connection.id) {
      throw BcrKnowledgeCacheFailure.changed;
    }
    final cached = await findSource(owner, connection.id);
    if (cached?.cacheRevision != lease.cacheRevision) {
      throw BcrKnowledgeCacheFailure.changed;
    }
    if (remote.snapshot case final snapshot?) {
      await _storeRemoteSnapshot(
        owner,
        connection.id,
        connection.label,
        connection.libraryUrl,
        snapshot,
      );
    } else if (cached == null) {
      throw BcrKnowledgeCacheFailure.changed;
    }
    await (_db.update(_db.knowledgeSourceConnections)..where(
          (row) =>
              row.ownerUserId.equals(owner) &
              row.sourceId.equals(connection.id),
        ))
        .write(
          KnowledgeSourceConnectionsCompanion(
            remoteHead: Value(remote.head),
            checkedAt: Value(DateTime.now().toUtc()),
          ),
        );
    await cancelSyncLease(owner, lease);
  });

  Future<void> disconnect(String owner, BcrKnowledgeConnection connection) =>
      _db.transaction(() async {
        final current = await findConnection(owner, connection.id);
        if (current?.revision != connection.revision) {
          throw BcrKnowledgeCacheFailure.changed;
        }
        await (_db.delete(_db.knowledgeSourceConnections)..where(
              (row) =>
                  row.ownerUserId.equals(owner) &
                  row.sourceId.equals(connection.id),
            ))
            .go();
        await (_db.delete(_db.knowledgeSourceCache)..where(
              (row) =>
                  row.ownerUserId.equals(owner) &
                  row.sourceId.equals(connection.id),
            ))
            .go();
        await (_db.delete(_db.knowledgeSourceImportLeases)..where(
              (row) =>
                  row.ownerUserId.equals(owner) &
                  row.sourceId.equals(connection.id),
            ))
            .go();
      });

  Future<void> _storeRemoteSnapshot(
    String owner,
    String id,
    String label,
    Uri url,
    BcrKnowledgeArchive snapshot,
  ) async {
    if (owner.isEmpty || label.trim().isEmpty || label.length > 200) {
      throw const FormatException('Invalid BCR connection');
    }
    final content = jsonEncode({
      'version': 1,
      'notes': snapshot.notes.map((note) => note.toJson()).toList(),
      'attachmentCount': snapshot.attachmentCount,
    });
    await _writeCache(
      owner: owner,
      id: id,
      label: label,
      url: url,
      content: content,
    );
  }

  BcrKnowledgeConnection _connection(KnowledgeSourceConnectionRow row) =>
      BcrKnowledgeConnection(
        target: BcrGithubTarget(
          owner: row.repositoryOwner,
          repository: row.repositoryName,
          branch: row.branch,
        ),
        label: row.label,
        libraryUrl: normalizeBcrLibraryUrl(row.libraryUrl),
        revision: row.revision,
        credentialId: row.credentialId,
        remoteHead: row.remoteHead,
        checkedAt: row.checkedAt,
      );
}
