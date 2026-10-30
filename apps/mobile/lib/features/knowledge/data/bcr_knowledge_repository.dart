import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/persistence/app_database.dart';
import '../domain/bcr_github_target.dart';
import '../domain/bcr_knowledge_connection.dart';
import '../domain/bcr_knowledge_models.dart';
import '../domain/bcr_knowledge_source.dart';
import 'bcr_github_client.dart';
import 'bcr_knowledge_archive.dart';

part 'bcr_knowledge_sync_repository.dart';

enum BcrKnowledgeCacheFailure implements Exception { changed, capacity }

class BcrKnowledgeRepository {
  const BcrKnowledgeRepository(this._db);

  static const maxCacheBytes = 32 * 1024 * 1024;
  final AppDatabase _db;

  /// Resets remove even a first import's lease, closing the null-baseline gap.
  Future<String> beginImport({
    required String owner,
    required Uri libraryUrl,
  }) async {
    final token = const Uuid().v4();
    await _db
        .into(_db.knowledgeSourceImportLeases)
        .insertOnConflictUpdate(
          KnowledgeSourceImportLeasesCompanion.insert(
            ownerUserId: owner,
            sourceId: bcrSourceId(
              normalizeBcrLibraryUrl(libraryUrl.toString()),
            ),
            token: token,
          ),
        );
    return token;
  }

  Future<void> cancelImport({
    required String owner,
    required Uri libraryUrl,
    required String token,
  }) async {
    await (_db.delete(_db.knowledgeSourceImportLeases)..where(
          (row) =>
              row.ownerUserId.equals(owner) &
              row.sourceId.equals(
                bcrSourceId(normalizeBcrLibraryUrl(libraryUrl.toString())),
              ) &
              row.token.equals(token),
        ))
        .go();
  }

  Stream<List<BcrKnowledgeSource>> watchSources(String owner) =>
      (_db.select(_db.knowledgeSourceCache)
            ..where((row) => row.ownerUserId.equals(owner))
            ..orderBy([(row) => OrderingTerm.desc(row.importedAt)]))
          .watch()
          .map((rows) => rows.map(_source).toList(growable: false));

  Future<List<BcrKnowledgeSource>> listSources(String owner) async =>
      (await (_db.select(
            _db.knowledgeSourceCache,
          )..where((row) => row.ownerUserId.equals(owner))).get())
          .map(_source)
          .toList(growable: false);

  Future<BcrKnowledgeSource?> findSource(String owner, String id) async {
    final row =
        await (_db.select(_db.knowledgeSourceCache)..where(
              (row) => row.ownerUserId.equals(owner) & row.sourceId.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _source(row);
  }

  /// Replaces exactly one library after validation and preview. No outbox writes.
  Future<void> importArchive({
    required String owner,
    required String label,
    required Uri libraryUrl,
    required BcrKnowledgeArchive archive,
    required String? expectedCacheRevision,
    required String importToken,
  }) async {
    if (owner.isEmpty || label.trim().isEmpty || label.length > 200) {
      throw const FormatException('Invalid BCR source');
    }
    final url = normalizeBcrLibraryUrl(libraryUrl.toString());
    final id = bcrSourceId(url);
    final content = jsonEncode({
      'version': 1,
      'notes': archive.notes.map((note) => note.toJson()).toList(),
      'attachmentCount': archive.attachmentCount,
    });
    await _db.transaction(() async {
      final lease =
          await (_db.select(_db.knowledgeSourceImportLeases)..where(
                (row) =>
                    row.ownerUserId.equals(owner) & row.sourceId.equals(id),
              ))
              .getSingleOrNull();
      if (lease?.token != importToken) throw BcrKnowledgeCacheFailure.changed;
      final current = await findSource(owner, id);
      if (current?.cacheRevision != expectedCacheRevision) {
        throw BcrKnowledgeCacheFailure.changed;
      }
      await _writeCache(
        owner: owner,
        id: id,
        label: label,
        url: url,
        content: content,
      );
      await cancelImport(owner: owner, libraryUrl: url, token: importToken);
    });
    AppLogger.instance.d(
      'knowledge.bcr.import notes=${archive.notes.length} '
      'attachments=${archive.attachmentCount}',
    );
  }

  Future<void> removeSource({
    required String owner,
    required String id,
    required String expectedCacheRevision,
  }) => _db.transaction(() async {
    final current = await findSource(owner, id);
    if (current?.cacheRevision != expectedCacheRevision) {
      throw BcrKnowledgeCacheFailure.changed;
    }
    await (_db.delete(_db.knowledgeSourceCache)..where(
          (row) => row.ownerUserId.equals(owner) & row.sourceId.equals(id),
        ))
        .go();
  });

  Future<void> _writeCache({
    required String owner,
    required String id,
    required String label,
    required Uri? url,
    required String content,
  }) async {
    final rows = await (_db.select(
      _db.knowledgeSourceCache,
    )..where((row) => row.ownerUserId.equals(owner))).get();
    final size =
        utf8.encode(content).length +
        rows
            .where((row) => row.sourceId != id)
            .fold(0, (sum, row) => sum + utf8.encode(row.contentJson).length);
    if (size > maxCacheBytes) throw BcrKnowledgeCacheFailure.capacity;
    // Keep the existing non-nullable column: an empty value has no page link.
    final libraryUrl = url?.toString() ?? '';
    final previous = rows.where((row) => row.sourceId == id).firstOrNull;
    if (previous?.contentJson == content &&
        previous?.label == label.trim() &&
        previous?.libraryUrl == libraryUrl) {
      return;
    }
    await _db
        .into(_db.knowledgeSourceCache)
        .insertOnConflictUpdate(
          KnowledgeSourceCacheCompanion.insert(
            ownerUserId: owner,
            sourceId: id,
            label: label.trim(),
            libraryUrl: libraryUrl,
            importedAt: DateTime.now().toUtc(),
            contentJson: content,
            cacheRevision: const Uuid().v4(),
          ),
        );
  }

  BcrKnowledgeSource _source(KnowledgeSourceCacheRow row) {
    final json = jsonDecode(row.contentJson) as Map<String, dynamic>;
    if (json['version'] != 1) throw const FormatException('Invalid BCR cache');
    return BcrKnowledgeSource(
      id: row.sourceId,
      label: row.label,
      libraryUrl: row.libraryUrl.isEmpty
          ? null
          : normalizeBcrLibraryUrl(row.libraryUrl),
      importedAt: row.importedAt,
      cacheRevision: row.cacheRevision,
      notes: (json['notes'] as List<dynamic>)
          .map(
            (note) => BcrKnowledgeNote.fromJson(
              (note as Map<String, dynamic>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      attachmentCount: json['attachmentCount'] as int,
    );
  }
}
