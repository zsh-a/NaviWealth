import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('localization copy does not expose implementation placeholders', () {
    for (final path in const ['lib/l10n/app_en.arb', 'lib/l10n/app_zh.arb']) {
      final file = File(path);
      final map = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final visibleValues = map.entries
          .where((entry) => !entry.key.startsWith('@'))
          .map((entry) => entry.value)
          .whereType<String>()
          .join('\n')
          .toLowerCase();

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
