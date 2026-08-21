/// KnowledgeOS image attachment metadata store (local-only, phase A).
///
/// Attachments are referenced from Note markdown as `![alt](attachment://<id>)`.
/// The metadata row lives in the local-only `knowledge_attachments` table;
/// the bytes live in platform [AttachmentStorage]. Neither rides sync v3 —
/// a row payload caps at 64 KiB — so images are device-local until a binary
/// channel exists. The schema already carries `sha256` + `mime_type` so a
/// future remote source can be added without a model change.
library;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/persistence/app_database.dart';
import '../../../../core/persistence/providers.dart';
import '../../domain/knowledge_text.dart';
import '../providers.dart' show kKnowledgeUuid;
import 'attachment_storage.dart';

/// Metadata for one stored image attachment.
class KnowledgeAttachment {
  const KnowledgeAttachment({
    required this.id,
    this.noteId,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    required this.sha256,
    required this.createdAt,
    required this.relativePath,
  });

  final String id;
  final String? noteId;
  final String fileName;
  final String mimeType;
  final int byteSize;
  final String sha256;
  final DateTime createdAt;

  /// Platform-storage path of the bytes.
  final String relativePath;

  /// The markdown `src` that references this attachment from a Note body.
  String get markdownSrc => '$kKnowledgeAttachmentScheme$id';
}

/// Policy for accepted image imports. Mirrors the finance ingest receipt
/// budget so one device's camera roll cannot produce pathological rows.
const int kKnowledgeAttachmentMaxBytes = 8 * 1024 * 1024;

/// Extension → mime allowlist for image imports.
const Map<String, String> kKnowledgeAttachmentImageTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'gif': 'image/gif',
};

class KnowledgeAttachmentImportRejected implements Exception {
  const KnowledgeAttachmentImportRejected(this.reason);

  final String reason;

  @override
  String toString() => 'KnowledgeAttachmentImportRejected: $reason';
}

/// Metadata + bytes lifecycle for knowledge image attachments.
class KnowledgeAttachmentStore {
  KnowledgeAttachmentStore({
    required AppDatabase db,
    AttachmentStorage? storage,
  }) : _db = db,
       _storage = storage ?? createAttachmentStorage();

  final AppDatabase _db;
  final AttachmentStorage _storage;

  /// False on web — the editor hides its insert affordance instead of
  /// failing at write time.
  bool get canWrite => _storage.isSupported;

  /// Imports image [bytes] as a new attachment and returns its metadata.
  ///
  /// Throws [KnowledgeAttachmentImportRejected] for oversize files or
  /// extensions outside [kKnowledgeAttachmentImageTypes].
  Future<KnowledgeAttachment> importImage({
    required String ownerUserId,
    required String fileName,
    required Uint8List bytes,
    String? noteId,
  }) async {
    final ext = fileName.split('.').last.toLowerCase();
    final mimeType = kKnowledgeAttachmentImageTypes[ext];
    if (mimeType == null) {
      throw KnowledgeAttachmentImportRejected('unsupported extension: $ext');
    }
    if (bytes.length > kKnowledgeAttachmentMaxBytes) {
      throw const KnowledgeAttachmentImportRejected('image exceeds 8 MiB');
    }

    final id = kKnowledgeUuid.v4();
    final storedName = '$id.$ext';
    final relativePath = await _storage.save(storedName, bytes);
    final attachment = KnowledgeAttachment(
      id: id,
      noteId: noteId,
      fileName: fileName,
      mimeType: mimeType,
      byteSize: bytes.length,
      sha256: sha256Bytes(bytes),
      createdAt: DateTime.now().toUtc(),
      relativePath: relativePath,
    );
    await _db.customStatement(
      'INSERT INTO knowledge_attachments '
      '(id, owner_user_id, note_id, file_name, mime_type, byte_size, sha256, '
      'created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        attachment.id,
        ownerUserId,
        attachment.noteId,
        attachment.fileName,
        attachment.mimeType,
        attachment.byteSize,
        attachment.sha256,
        attachment.createdAt.millisecondsSinceEpoch,
      ],
    );
    return attachment;
  }

  /// Looks up one attachment's metadata by id.
  Future<KnowledgeAttachment?> find(String id) async {
    final rows = await _db
        .customSelect(
          'SELECT id, note_id, file_name, mime_type, byte_size, sha256, '
          'created_at FROM knowledge_attachments WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return KnowledgeAttachment(
      id: row.read<String>('id'),
      noteId: row.read<String?>('note_id'),
      fileName: row.read<String>('file_name'),
      mimeType: row.read<String>('mime_type'),
      byteSize: row.read<int>('byte_size'),
      sha256: row.read<String>('sha256'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      // The relative path is deterministic from the id + file extension.
      relativePath:
          'knowledge_attachments/${row.read<String>('id')}.'
          '${row.read<String>('file_name').split('.').last.toLowerCase()}',
    );
  }

  /// Reads the bytes for [id]; null when metadata or bytes are missing
  /// (e.g. a note synced from another device, or web).
  Future<Uint8List?> readBytes(String id) async {
    final attachment = await find(id);
    if (attachment == null) return null;
    return _storage.read(attachment.relativePath);
  }

  /// Binds an orphan attachment to its owning Note after the note is saved.
  Future<void> bindToNote(String id, String noteId) {
    return _db.customStatement(
      'UPDATE knowledge_attachments SET note_id = ? WHERE id = ?',
      <Object?>[noteId, id],
    );
  }
}

/// Hex sha256 of attachment bytes, exposed for tests and a future sync
/// channel's integrity checks.
String sha256Bytes(Uint8List bytes) => sha256.convert(bytes).toString();

final knowledgeAttachmentStoreProvider =
    FutureProvider<KnowledgeAttachmentStore>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      return KnowledgeAttachmentStore(db: db);
    });
