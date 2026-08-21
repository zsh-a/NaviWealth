import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'attachment_storage.dart';

/// Filesystem-backed [AttachmentStorage] for native platforms.
///
/// Attachments live in `<app documents>/knowledge_attachments/` so they sit
/// next to user data (and inside the OS backup scope on iOS/Android),
/// matching how the Drift database file is placed. Writes go through a
/// `.partial` temp file so a crash mid-write never leaves a truncated image
/// under the final name.
class IoAttachmentStorage implements AttachmentStorage {
  IoAttachmentStorage({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  static const String _subdir = 'knowledge_attachments';

  @override
  bool get isSupported => true;

  Future<Directory> _dir() async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String> save(String fileName, Uint8List bytes) async {
    final dir = await _dir();
    final target = File(p.join(dir.path, fileName));
    final partial = File('${target.path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(target.path);
    return p.join(_subdir, fileName);
  }

  @override
  Future<Uint8List?> read(String relativePath) async {
    final docs = await _documentsDirectory();
    final file = File(p.join(docs.path, relativePath));
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> delete(String relativePath) async {
    final docs = await _documentsDirectory();
    final file = File(p.join(docs.path, relativePath));
    if (file.existsSync()) await file.delete();
  }
}

AttachmentStorage createAttachmentStorageImpl() => IoAttachmentStorage();
