import 'dart:typed_data';

import 'attachment_storage.dart';

/// Web / unsupported-platform [AttachmentStorage].
///
/// Web has no `dart:io` filesystem; phase A degrades gracefully — the UI
/// hides insert affordances when [isSupported] is false, and existing
/// `attachment://` references render as a placeholder chip.
class UnsupportedAttachmentStorage implements AttachmentStorage {
  const UnsupportedAttachmentStorage();

  @override
  bool get isSupported => false;

  @override
  Future<String> save(String fileName, Uint8List bytes) {
    throw UnsupportedError('Attachment storage is not available on web');
  }

  @override
  Future<Uint8List?> read(String relativePath) async => null;

  @override
  Future<void> delete(String relativePath) async {}
}

AttachmentStorage createAttachmentStorageImpl() =>
    const UnsupportedAttachmentStorage();
