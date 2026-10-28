import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A read-only snapshot of a BCR note. This is not a synced KnowledgeOS Note.
class BcrKnowledgeNote {
  BcrKnowledgeNote({
    required this.id,
    required this.title,
    required this.body,
    required List<String> tags,
    this.path,
    this.collectionId,
    required DateTime createdAt,
    required DateTime updatedAt,
    required List<Map<String, Object?>> citations,
  }) : tags = List<String>.unmodifiable(tags),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       citations = List<Map<String, Object?>>.unmodifiable(
         citations.map((citation) => _jsonMap(citation, 0)),
       ) {
    if (!isValidBcrKnowledgeId(id) ||
        title.length > 500 ||
        body.length > 500000 ||
        this.tags.length > 100 ||
        this.tags.any((tag) => tag.length > 100) ||
        (collectionId != null && !isValidBcrKnowledgeId(collectionId!)) ||
        this.createdAt.millisecondsSinceEpoch < 0 ||
        this.updatedAt.millisecondsSinceEpoch < 0) {
      throw const FormatException('Invalid BCR note fields');
    }
    if (path != null) validateBcrKnowledgePath(path!, note: true);
    _validateCitations(this.citations);
    // A Navi snapshot fingerprint, deliberately distinct from BCR's BLAKE3
    // revision. Sorted nested keys make it independent of JSON key order.
    fingerprint =
        'sha256:${sha256.convert(utf8.encode(jsonEncode(_fields())))}';
  }

  final String id;
  final String title;
  final String body;
  final List<String> tags;
  final String? path;
  final String? collectionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Map<String, Object?>> citations;
  late final String fingerprint;

  factory BcrKnowledgeNote.fromJson(Map<String, Object?> json) {
    final tags = json['tags'];
    final citations = json['citations'];
    if (json['id'] is! String ||
        json['title'] is! String ||
        json['body'] is! String ||
        tags is! List ||
        citations is! List ||
        tags.any((tag) => tag is! String) ||
        (json['path'] != null && json['path'] is! String) ||
        (json['collectionId'] != null && json['collectionId'] is! String)) {
      throw const FormatException('Invalid BCR note');
    }
    final note = BcrKnowledgeNote(
      id: json['id']! as String,
      title: json['title']! as String,
      body: json['body']! as String,
      tags: tags.cast<String>(),
      path: json['path'] as String?,
      collectionId: json['collectionId'] as String?,
      createdAt: _time(json['createdAt']),
      updatedAt: _time(json['updatedAt']),
      citations: citations.map((value) => _jsonMap(value, 0)).toList(),
    );
    if (json.containsKey('fingerprint') &&
        json['fingerprint'] != note.fingerprint) {
      throw const FormatException('BCR snapshot fingerprint mismatch');
    }
    return note;
  }

  Map<String, Object?> _fields() => <String, Object?>{
    'id': id,
    'title': title,
    if (path != null) 'path': path,
    'body': body,
    'tags': tags,
    'collectionId': collectionId,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'citations': citations,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ..._fields(),
    'fingerprint': fingerprint,
  };
}

/// BCR ids remain stable across title and logical-path changes.
bool isValidBcrKnowledgeId(String value) =>
    RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,99}$').hasMatch(value) &&
    !const <String>{
      'constructor',
      'toString',
      'toLocaleString',
      'valueOf',
      'hasOwnProperty',
      'isPrototypeOf',
      'propertyIsEnumerable',
      'prototype',
    }.contains(value);

/// Logical vault paths are metadata, never filesystem extraction targets.
void validateBcrKnowledgePath(String value, {required bool note}) {
  final segments = value.split('/');
  if (value.isEmpty ||
      value.length > 500 ||
      (note && !value.toLowerCase().endsWith('.md')) ||
      segments.any(
        (part) =>
            part.isEmpty ||
            part.startsWith('.') ||
            part.length > 120 ||
            part != part.trim() ||
            part.endsWith('.') ||
            RegExp(r'[\\<>:"|?*#%\x00-\x1f\x7f]').hasMatch(part) ||
            RegExp(
              r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
              caseSensitive: false,
            ).hasMatch(part),
      )) {
    throw const FormatException('Invalid BCR logical path');
  }
}

DateTime _time(Object? value) {
  if (value is! int || value < 0 || value > 8640000000000000) {
    throw const FormatException('Invalid BCR timestamp');
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

Map<String, Object?> _jsonMap(Object? value, int depth) {
  if (value is! Map || depth > 24 || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid BCR citation object');
  }
  final keys = value.keys.cast<String>().toList()..sort();
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final key in keys) key: _jsonValue(value[key], depth + 1),
  });
}

Object? _jsonValue(Object? value, int depth) {
  if (depth > 24) {
    throw const FormatException('BCR citation is too deeply nested');
  }
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is Map) return _jsonMap(value, depth);
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map((item) => _jsonValue(item, depth + 1)),
    );
  }
  throw const FormatException('Invalid BCR citation value');
}

void _validateCitations(List<Map<String, Object?>> citations) {
  if (citations.length > 500 ||
      utf8.encode(jsonEncode(citations)).length > 2 * 1024 * 1024) {
    throw const FormatException('BCR citations exceed the size limit');
  }
  final ids = <String>{};
  for (final citation in citations) {
    if (const <String>[
          'id',
          'documentId',
          'title',
          'source',
          'route',
          'text',
          'note',
        ].any((key) => citation[key] is! String) ||
        (citation['id']! as String).isEmpty ||
        !ids.add(citation['id']! as String)) {
      throw const FormatException('Invalid BCR citation');
    }
    final route = citation['route']! as String;
    final savedAt = citation['savedAt'];
    if (!RegExp(r'^/(reader|documents|media|manga)(?:\?|$)').hasMatch(route) ||
        RegExp(r'[\x00-\x20\\]').hasMatch(route) ||
        savedAt is! num ||
        !savedAt.isFinite ||
        savedAt.abs() > 8640000000000000) {
      throw const FormatException('Invalid BCR citation provenance');
    }
  }
}
