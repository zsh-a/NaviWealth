import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bcr_knowledge_models.dart';

/// A connected BCR page identifies a library; titles and backup names do not.
Uri normalizeBcrLibraryUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !const ['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      value.length > 2048) {
    throw const FormatException('Invalid BCR library URL');
  }
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.isEmpty) path = '/knowledge';
  return uri.replace(path: path);
}

String bcrSourceId(Uri libraryUrl) =>
    'bcr-${sha256.convert(utf8.encode(libraryUrl.toString()))}';

class BcrKnowledgeSource {
  BcrKnowledgeSource({
    required this.id,
    required this.label,
    required this.importedAt,
    required this.cacheRevision,
    required List<BcrKnowledgeNote> notes,
    required this.attachmentCount,
    this.libraryUrl,
  }) : notes = List.unmodifiable(notes);

  final String id;
  final String label;
  final Uri? libraryUrl;
  final DateTime importedAt;

  /// Local optimistic-save token, distinct from every content fingerprint.
  final String cacheRevision;
  final List<BcrKnowledgeNote> notes;
  final int attachmentCount;

  Uri? noteUrl(String noteId) =>
      libraryUrl?.replace(queryParameters: {'note': noteId});
}

class BcrKnowledgeHit {
  const BcrKnowledgeHit({required this.source, required this.note});

  final BcrKnowledgeSource source;
  final BcrKnowledgeNote note;
}

/// Offsets stay in UTF-16 units, while page edges preserve complete scalars.
({int offset, int? nextOffset, String text}) bcrTextPage(
  String body,
  int offset, {
  int length = 12000,
}) {
  if (offset < 0 || offset > body.length || length < 2) {
    throw const FormatException('Invalid BCR text page');
  }
  final start = _scalarBoundary(body, offset);
  final end = _scalarBoundary(body, (start + length).clamp(0, body.length));
  return (
    offset: start,
    nextOffset: end < body.length ? end : null,
    text: body.substring(start, end),
  );
}

int _scalarBoundary(String value, int offset) {
  if (offset > 0 &&
      offset < value.length &&
      value.codeUnitAt(offset) >= 0xdc00 &&
      value.codeUnitAt(offset) <= 0xdfff &&
      value.codeUnitAt(offset - 1) >= 0xd800 &&
      value.codeUnitAt(offset - 1) <= 0xdbff) {
    return offset - 1;
  }
  return offset;
}

/// Searches every cached note, independently of the bounded Memory index.
List<BcrKnowledgeHit> searchBcrKnowledge(
  Iterable<BcrKnowledgeSource> sources,
  String query, {
  int limit = 50,
}) {
  final needle = query.trim().toLowerCase();
  int score(BcrKnowledgeNote note) {
    if (needle.isEmpty) return 1;
    final title = note.title.toLowerCase();
    if (title == needle) return 5;
    if (title.contains(needle)) return 4;
    if (note.tags.any((tag) => tag.toLowerCase().contains(needle))) return 3;
    if ((note.path ?? '').toLowerCase().contains(needle)) return 2;
    return note.body.toLowerCase().contains(needle) ? 1 : 0;
  }

  final hits = <({BcrKnowledgeHit hit, int score})>[];
  for (final source in sources) {
    for (final note in source.notes) {
      final rank = score(note);
      if (rank > 0) {
        hits.add((
          hit: BcrKnowledgeHit(source: source, note: note),
          score: rank,
        ));
      }
    }
  }
  hits.sort((a, b) {
    final ranked = b.score.compareTo(a.score);
    if (ranked != 0) return ranked;
    final time = b.hit.note.updatedAt.compareTo(a.hit.note.updatedAt);
    if (time != 0) return time;
    return '${a.hit.source.id}/${a.hit.note.id}'.compareTo(
      '${b.hit.source.id}/${b.hit.note.id}',
    );
  });
  return hits.take(limit).map((entry) => entry.hit).toList(growable: false);
}

/// Captured into the ordinary Decision rationale, never recomputed on refresh.
class BcrKnowledgeReference {
  BcrKnowledgeReference.fromHit(BcrKnowledgeHit hit, {String query = ''})
    : sourceId = hit.source.id,
      noteId = hit.note.id,
      title = hit.note.title,
      sourceLabel = hit.source.label,
      url = hit.source.noteUrl(hit.note.id),
      fingerprint = hit.note.fingerprint,
      updatedAt = hit.note.updatedAt,
      excerpt = _excerpt(hit.note.body, query);

  final String sourceId;
  final String noteId;
  final String title;
  final String sourceLabel;
  final Uri? url;
  final String fingerprint;
  final DateTime updatedAt;
  final String excerpt;

  String toMarkdown() {
    final link = url;
    final heading = link == null
        ? _escape(title)
        : '[${_linkLabel(title)}](${link.toString().replaceAll('(', '%28').replaceAll(')', '%29')})';
    return '$heading · ${_escape(sourceLabel)}\n\n'
        '${excerpt.split('\n').map((line) => '> $line').join('\n')}\n\n'
        '`$sourceId/$noteId`  \n'
        '`$fingerprint` · ${updatedAt.toUtc().toIso8601String()}';
  }

  // The app's lightweight link renderer reads labels literally. Neutralize
  // bracket delimiters while preserving readable titles in both renderers.
  static String _linkLabel(String value) => value
      .replaceAll(RegExp(r'[\r\n\u0000-\u001f]'), ' ')
      .replaceAll('[', '［')
      .replaceAll(']', '］');

  static String _escape(String value) => value
      .replaceAll(RegExp(r'[\r\n\u0000-\u001f]'), ' ')
      .replaceAllMapped(RegExp(r'[\\`*_{}\[\]()#+.!<>|~]'), (m) => '\\${m[0]}');

  static String _excerpt(String body, String query) {
    final needle = query.trim().toLowerCase();
    final at = needle.isEmpty ? 0 : body.toLowerCase().indexOf(needle);
    final start = _scalarBoundary(
      body,
      (at > 200 ? at - 200 : 0).clamp(0, body.length),
    );
    // Avoid splitting UTF-16 surrogate pairs in captured text.
    final points = body.substring(start).runes.take(1200).toList();
    return '${start > 0 ? '…\n' : ''}${String.fromCharCodes(points)}'
        '${body.substring(start).runes.length > points.length ? '\n…' : ''}';
  }
}
