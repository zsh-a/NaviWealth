import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// The public loader has no alias/depth budget. Check events before it builds
// nodes or hashes structural keys; yaml is pinned to 3.1.4 for this integration.
// ignore: implementation_imports
import 'package:yaml/src/event.dart' show EventType;
// ignore: implementation_imports
import 'package:yaml/src/parser.dart' show Parser;
import 'package:yaml/yaml.dart';

import '../domain/bcr_knowledge_models.dart';

const _maxZipBytes = 64 * 1024 * 1024;
const _maxTextBytes = 16 * 1024 * 1024;
const _maxFileBytes = 2 * 1024 * 1024;
const _maxDeclaredBytes = 512 * 1024 * 1024;
const _manifestPath = 'knowledge/manifest.json';

/// Reads a bounded, read-only BCR projection from ZIP or validated Git files.
/// Attachment bytes are neither decompressed, copied nor verified here.
class BcrKnowledgeArchive {
  BcrKnowledgeArchive._(List<BcrKnowledgeNote> notes, this.attachmentCount)
    : notes = List<BcrKnowledgeNote>.unmodifiable(notes);

  final List<BcrKnowledgeNote> notes;
  final int attachmentCount;

  /// Validated Git text files use the same content contract as ZIP backups.
  factory BcrKnowledgeArchive.fromFiles(
    Map<String, String> files, {
    Map<String, int> attachmentSizes = const {},
  }) => _guardRead(() => _fromFiles(files, attachmentSizes));

  factory BcrKnowledgeArchive.decode(Uint8List bytes) =>
      _guardRead(() => _decode(bytes));
}

BcrKnowledgeArchive _guardRead(BcrKnowledgeArchive Function() read) {
  try {
    return read();
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Invalid BCR knowledge source');
  }
}

BcrKnowledgeArchive _decode(Uint8List bytes) {
  final count = _preflight(bytes);
  // ZipDecoder coalesces duplicate paths and can eagerly read symlinks. Read
  // its public directory API instead, retaining every header before inflation.
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  if (directory.fileHeaders.length != count) {
    throw const FormatException('Incomplete BCR ZIP directory');
  }
  final texts = <String, ZipFileHeader>{};
  final binaries = <String, ZipFileHeader>{};
  final seen = <String>{};
  var declared = 0;
  var textDeclared = 0;
  for (final header in directory.fileHeaders) {
    final path = header.filename;
    final file = header.file;
    if (path.isEmpty ||
        path.length > 250 ||
        path.startsWith('/') ||
        path.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        path.split('/').any((part) => part == '.' || part == '..') ||
        !seen.add(path)) {
      throw const FormatException('Duplicate or unsafe BCR ZIP path');
    }
    final type = (header.externalFileAttributes >> 16) & 0xf000;
    if (file == null ||
        file.filename != path ||
        (header.generalPurposeBitFlag | file.flags) & 1 != 0 ||
        type == 0xa000 ||
        (type != 0 && type != 0x8000 && type != 0x4000) ||
        header.diskNumberStart != 0 ||
        !const <int>{0, 8}.contains(header.compressionMethod) ||
        file.compressedSize != header.compressedSize ||
        file.uncompressedSize != header.uncompressedSize ||
        file.getRawContent().length != header.compressedSize) {
      throw const FormatException('Unsupported or corrupt BCR ZIP entry');
    }
    declared += header.uncompressedSize;
    if (declared > _maxDeclaredBytes) {
      throw const FormatException('BCR backup exceeds its expanded size limit');
    }
    if (path.endsWith('/')) {
      if (!const <String>{
            'knowledge/',
            'knowledge/notes/',
            'knowledge/citations/',
            'knowledge/collections/',
            'knowledge/attachments/',
          }.contains(path) ||
          header.uncompressedSize != 0) {
        throw const FormatException('Unknown BCR ZIP directory');
      }
      continue;
    }
    if (type == 0x4000) {
      throw const FormatException('Invalid BCR directory entry');
    }
    final binary = RegExp(r'^knowledge/attachments/([a-f0-9]{64})\.bin$')
        .firstMatch(path);
    if (binary != null) {
      if (header.uncompressedSize > 128 * 1024 * 1024) {
        throw const FormatException('BCR attachment exceeds its size limit');
      }
      binaries[binary.group(1)!] = header;
      continue;
    }
    if (!isBcrKnowledgeTextPath(path)) {
      throw const FormatException('Unknown BCR backup file');
    }
    textDeclared += header.uncompressedSize;
    if (header.uncompressedSize > _maxFileBytes ||
        textDeclared > _maxTextBytes) {
      throw const FormatException('BCR text exceeds its size limit');
    }
    texts[path] = header;
  }
  final files = <String, String>{};
  var actualTextBytes = 0;
  for (final entry in texts.entries) {
    final output = _BoundedOutput();
    final raw = entry.value.file!.getRawContent();
    if (entry.value.compressionMethod == 8) {
      // Unlike decodeBytes, this accepts a bounded destination on Web too.
      Inflate(raw, output: output);
    } else {
      output.writeBytes(raw);
    }
    final content = output.getBytes();
    actualTextBytes += content.length;
    if (content.length != entry.value.uncompressedSize ||
        getCrc32(content) != entry.value.crc32 ||
        actualTextBytes > _maxTextBytes) {
      throw const FormatException('Corrupt or oversized BCR text');
    }
    files[entry.key] = utf8.decode(content, allowMalformed: false);
  }
  return _fromFiles(files, {
    for (final entry in binaries.entries)
      entry.key: entry.value.uncompressedSize,
  });
}

BcrKnowledgeArchive _fromFiles(
  Map<String, String> files,
  Map<String, int> attachmentSizes,
) {
  if (files.length > 11010 || attachmentSizes.length > 10000) {
    throw const FormatException('Too many BCR files');
  }
  var total = 0;
  for (final entry in files.entries) {
    final size = utf8.encode(entry.value).length;
    total += size;
    if (!isBcrKnowledgeTextPath(entry.key) ||
        size > _maxFileBytes ||
        total > _maxTextBytes) {
      throw const FormatException('Invalid or oversized BCR text file');
    }
  }
  for (final entry in attachmentSizes.entries) {
    total += entry.value;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) ||
        entry.value < 0 ||
        entry.value > 128 * 1024 * 1024 ||
        total > _maxDeclaredBytes) {
      throw const FormatException('Invalid BCR attachment size');
    }
  }
  final manifest = _object(_requiredJson(files, _manifestPath));
  final version = manifest['version'];
  if (manifest['format'] != 'bcr-knowledge' ||
      version is! int ||
      version < 1 ||
      version > 4) {
    throw const FormatException('Unsupported BCR backup format');
  }
  final folderText = files['knowledge/folders.json'];
  if ((version == 3 && folderText == null) ||
      (version < 3 && folderText != null)) {
    throw const FormatException('Invalid BCR folders manifest');
  }
  if (folderText != null) {
    final folders = jsonDecode(folderText) as Object?;
    if (folders is! List || folders.length > 2000) {
      throw const FormatException('Invalid BCR folders');
    }
    final seen = <String>{};
    for (final folder in folders) {
      if (folder is! String || !seen.add(folder.toLowerCase())) {
        throw const FormatException('Invalid BCR folder');
      }
      validateBcrKnowledgePath(folder, note: false);
    }
  }
  final collections = <String>{};
  for (final entry in files.entries) {
    final id = _partId(entry.key, 'collections', '.json');
    if (id == null) continue;
    final collection = _object(jsonDecode(entry.value));
    if (!isValidBcrKnowledgeId(id) ||
        collection['id'] != id ||
        collection['name'] is! String ||
        (collection['name']! as String).length > 200 ||
        !collections.add(id) ||
        collections.length > 1000) {
      throw const FormatException('Invalid BCR collection');
    }
  }
  final notes = <BcrKnowledgeNote>[];
  final noteIds = <String>{};
  for (final entry in files.entries) {
    final id = _partId(entry.key, 'notes', '.md');
    if (id == null) continue;
    final match = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)')
        .firstMatch(entry.value);
    if (match == null || match.group(1)!.length > 32000) {
      throw const FormatException('Missing BCR note metadata');
    }
    _preflightYaml(match.group(1)!);
    final yaml = _yamlJson(loadYamlNode(match.group(1)!));
    final metadata = _object(yaml);
    if (!const <int>{1, 2}.contains(metadata['bcr']) ||
        metadata['id'] != id ||
        !metadata.containsKey('collectionId')) {
      throw const FormatException('Invalid BCR note identity');
    }
    final citations = _requiredJson(files, 'knowledge/citations/$id.json');
    final note = BcrKnowledgeNote.fromJson(<String, Object?>{
      ...metadata,
      'body': entry.value.substring(match.end),
      'citations': citations,
    });
    if ((note.collectionId != null &&
            !collections.contains(note.collectionId)) ||
        !noteIds.add(id) ||
        notes.length >= 5000) {
      throw const FormatException('Missing BCR collection or too many notes');
    }
    notes.add(note);
  }
  for (final path in files.keys) {
    final id = _partId(path, 'citations', '.json');
    if (id != null && !noteIds.contains(id)) {
      throw const FormatException('BCR citation has no corresponding note');
    }
  }
  final attachmentCount = _attachments(files, attachmentSizes, version);
  notes.sort((a, b) => a.id.compareTo(b.id));
  return BcrKnowledgeArchive._(notes, attachmentCount);
}

int _preflight(Uint8List bytes) {
  if (bytes.length > _maxZipBytes || bytes.length < 22) {
    throw const FormatException('BCR ZIP must be at most 64 MiB');
  }
  final data = ByteData.sublistView(bytes);
  final minimum = bytes.length > 65557 ? bytes.length - 65557 : 0;
  for (var offset = bytes.length - 22; offset >= minimum; offset--) {
    if (data.getUint32(offset, Endian.little) != 0x06054b50) continue;
    if (offset + 22 + data.getUint16(offset + 20, Endian.little) !=
        bytes.length) {
      continue;
    }
    final count = data.getUint16(offset + 10, Endian.little);
    final directorySize = data.getUint32(offset + 12, Endian.little);
    final directoryOffset = data.getUint32(offset + 16, Endian.little);
    if (data.getUint16(offset + 4, Endian.little) != 0 ||
        data.getUint16(offset + 6, Endian.little) != 0 ||
        data.getUint16(offset + 8, Endian.little) != count ||
        count > 22010 ||
        directoryOffset + directorySize != offset) {
      throw const FormatException('Unsupported BCR ZIP directory');
    }
    // ZipDirectory.read parses until the end of the directory, independently
    // of EOCD's declared count. Validate the actual count before it can allocate
    // a ZipFileHeader/ZipFile pair for every attacker-supplied record.
    var cursor = directoryOffset;
    var actualCount = 0;
    while (cursor < offset) {
      if (cursor + 46 > offset ||
          data.getUint32(cursor, Endian.little) != 0x02014b50) {
        throw const FormatException('Invalid BCR ZIP directory record');
      }
      actualCount++;
      if (actualCount > count || actualCount > 22010) {
        throw const FormatException('BCR ZIP directory entry count differs');
      }
      final next =
          cursor +
          46 +
          data.getUint16(cursor + 28, Endian.little) +
          data.getUint16(cursor + 30, Endian.little) +
          data.getUint16(cursor + 32, Endian.little);
      if (next > offset) {
        throw const FormatException('Truncated BCR ZIP directory record');
      }
      cursor = next;
    }
    if (cursor != offset || actualCount != count) {
      throw const FormatException('BCR ZIP directory entry count differs');
    }
    // ZIP64/multipart containers are unnecessary inside this adapter's limits.
    return count;
  }
  throw const FormatException('Missing BCR ZIP directory');
}

bool isBcrKnowledgeTextPath(String path) =>
    const <String>{
      _manifestPath,
      'knowledge/folders.json',
      'knowledge/attachments.json',
    }.contains(path) ||
    RegExp(
      r'^knowledge/(notes/[^/]+\.md|citations/[^/]+\.json|collections/[^/]+\.json)$',
    ).hasMatch(path);

String? _partId(String path, String directory, String suffix) {
  final prefix = 'knowledge/$directory/';
  return path.startsWith(prefix) && path.endsWith(suffix)
      ? path.substring(prefix.length, path.length - suffix.length)
      : null;
}

Object? _requiredJson(Map<String, String> files, String path) {
  final raw = files[path];
  if (raw == null) throw const FormatException('Missing BCR backup file');
  return jsonDecode(raw);
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid BCR metadata object');
  }
  return value.cast<String, Object?>();
}

// Event preflight already bounds depth and excludes aliases/structural keys.
Object? _yamlJson(YamlNode node) {
  if (node is YamlMap) {
    return <String, Object?>{
      for (final entry in node.nodes.entries)
        (entry.key as YamlScalar).value as String: _yamlJson(entry.value),
    };
  }
  if (node is YamlList) {
    return node.nodes.map(_yamlJson).toList();
  }
  return node.value as Object?;
}

void _preflightYaml(String source) {
  final parser = Parser(source);
  final stack = <_YamlFrame>[];
  var documents = 0;
  var events = 0;
  while (!parser.isDone) {
    final type = parser.parse().type;
    if (++events > 4096) {
      throw const FormatException('BCR YAML has too many nodes');
    }
    if (type == EventType.alias) {
      throw const FormatException('BCR YAML aliases are not supported');
    }
    if (type == EventType.documentStart && ++documents > 1) {
      throw const FormatException('BCR YAML must contain one document');
    }
    final mapping = type == EventType.mappingStart;
    final sequence = type == EventType.sequenceStart;
    if (mapping || sequence || type == EventType.scalar) {
      if (stack.isNotEmpty && stack.last.mapping) {
        final parent = stack.last;
        if (parent.key && (mapping || sequence)) {
          throw const FormatException('BCR YAML mapping keys must be scalars');
        }
        parent.key = !parent.key;
      }
      if (mapping || sequence) {
        stack.add(_YamlFrame(mapping));
        if (stack.length > 16) {
          throw const FormatException('BCR YAML nesting exceeds its limit');
        }
      }
    } else if (type == EventType.mappingEnd || type == EventType.sequenceEnd) {
      stack.removeLast();
    }
  }
}

class _YamlFrame {
  _YamlFrame(this.mapping);
  final bool mapping;
  bool key = true;
}

int _attachments(
  Map<String, String> files,
  Map<String, int> binaries,
  int version,
) {
  final raw = files['knowledge/attachments.json'];
  if (version != 4) {
    if (raw != null || binaries.isNotEmpty) {
      throw const FormatException('Unexpected BCR attachments');
    }
    return 0;
  }
  if (raw == null) {
    throw const FormatException('Missing BCR attachment manifest');
  }
  final records = _object(jsonDecode(raw));
  if (records.length > 10000) {
    throw const FormatException('Too many BCR attachments');
  }
  final hashes = <String, int>{};
  for (final entry in records.entries) {
    final value = _object(entry.value);
    final hash = value['hash'];
    final size = value['size'];
    final name = value['name'];
    final mime = value['mime'];
    final createdAt = value['createdAt'];
    if (!isValidBcrKnowledgeId(entry.key) ||
        value['id'] != entry.key ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        size is! int ||
        size < 0 ||
        size > 128 * 1024 * 1024 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 500 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        mime is! String ||
        !RegExp(r'^[a-z\d!#$&^_.+-]+/[a-z\d!#$&^_.+-]+$').hasMatch(mime) ||
        createdAt is! int ||
        createdAt < 0 ||
        createdAt > 8640000000000000 ||
        (hashes.containsKey(hash) && hashes[hash] != size) ||
        binaries[hash] != size) {
      throw const FormatException('Invalid BCR attachment metadata');
    }
    for (final key in const <String>['width', 'height']) {
      final dimension = value[key];
      if (dimension != null &&
          (dimension is! int || dimension < 1 || dimension > 100000)) {
        throw const FormatException('Invalid BCR attachment dimensions');
      }
    }
    hashes[hash] = size;
  }
  if (hashes.length != binaries.length) {
    throw const FormatException('BCR attachment files and manifest differ');
  }
  return records.length;
}

/// Bounds actual inflation, including forged ZIP size declarations.
class _BoundedOutput extends OutputMemoryStream {
  void _check(int count) {
    if (count < 0 || length + count > _maxFileBytes) {
      throw const FormatException('BCR text inflation exceeds its size limit');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
