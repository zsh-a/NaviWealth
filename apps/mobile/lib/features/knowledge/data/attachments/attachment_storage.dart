/// Platform binary storage for KnowledgeOS image attachments.
///
/// Conditional-imported: native platforms write real files under the app
/// documents directory; web/unsupported platforms get a stub whose
/// [AttachmentStorage.isSupported] is false so the UI can hide insert
/// affordances instead of failing at write time.
library;

import 'dart:typed_data';

import 'attachment_storage_stub.dart'
    if (dart.library.io) 'attachment_storage_io.dart';

/// Binary blob store backing the `knowledge_attachments` metadata table.
abstract class AttachmentStorage {
  /// Whether this platform can persist attachment bytes at all.
  bool get isSupported;

  /// Persists [bytes] under [fileName] and returns the stored relative path.
  Future<String> save(String fileName, Uint8List bytes);

  /// Reads the bytes stored at [relativePath]; null when missing.
  Future<Uint8List?> read(String relativePath);

  /// Deletes the bytes stored at [relativePath]; missing files are a no-op.
  Future<void> delete(String relativePath);
}

AttachmentStorage createAttachmentStorage() => createAttachmentStorageImpl();
