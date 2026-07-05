import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English and Chinese ARB files expose the same visible messages', () {
    final enArb = _readArb('lib/l10n/app_en.arb');
    final zhArb = _readArb('lib/l10n/app_zh.arb');
    final en = _visibleMessages(enArb);
    final zh = _visibleMessages(zhArb);

    expect(zh.keys.toSet(), en.keys.toSet());

    for (final key in en.keys) {
      final placeholders = _metadataPlaceholderNames(enArb, key);
      final zhPlaceholders = _metadataPlaceholderNames(zhArb, key);
      if (zhPlaceholders.isNotEmpty) {
        expect(zhPlaceholders, placeholders, reason: 'ARB metadata for $key');
      }
      expect(
        placeholders.where((name) => !_usesPlaceholder(en[key]!, name)),
        isEmpty,
        reason: 'English message does not reference its metadata for $key',
      );
      expect(
        placeholders.where((name) => !_usesPlaceholder(zh[key]!, name)),
        isEmpty,
        reason:
            'Chinese message does not reference placeholder metadata for $key',
      );
    }
  });

  test('localization copy does not expose implementation placeholders', () {
    for (final path in const ['lib/l10n/app_en.arb', 'lib/l10n/app_zh.arb']) {
      final visibleValues = _visibleMessages(
        _readArb(path),
      ).values.join('\n').toLowerCase();

      expect(visibleValues, isNot(contains('fir-')), reason: path);
      expect(visibleValues, isNot(contains('coming soon')), reason: path);
      expect(visibleValues, isNot(contains('placeholder')), reason: path);
      expect(visibleValues, isNot(contains('占位')), reason: path);
      expect(visibleValues, isNot(contains('即将推出')), reason: path);
      expect(visibleValues, isNot(contains('web continues to use cloud ai')));
      expect(visibleValues, isNot(contains('web 继续使用云端 ai')));
      expect(visibleValues, isNot(contains('web 继续使用云端ai')));
    }
  });
}

Map<String, Object?> _readArb(String path) {
  final file = File(path);
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

Map<String, String> _visibleMessages(Map<String, Object?> map) {
  return {
    for (final entry in map.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value! as String,
  };
}

Set<String> _metadataPlaceholderNames(Map<String, Object?> arb, String key) {
  final meta = arb['@$key'];
  if (meta is! Map) return const <String>{};
  final placeholders = meta['placeholders'];
  if (placeholders is! Map) return const <String>{};
  return placeholders.keys.cast<String>().toSet();
}

bool _usesPlaceholder(String message, String name) =>
    RegExp('\\{$name(?:\\}|,)').hasMatch(message);
