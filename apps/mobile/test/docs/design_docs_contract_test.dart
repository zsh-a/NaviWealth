import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project docs describe the current IA without historical issue tags', () {
    final markdownFiles = <File>[
      File('README.md'),
      ...Directory('docs')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.md')),
    ];

    final legacyTopLevelRoute = RegExp(
      r'''(^|[\s`'"(\[{>])/(assets|accounts|expenses|analytics|fire|rebalance|me|more|transactions)(?=$|/|[\s`'"),\].<])''',
      multiLine: true,
    );

    for (final file in markdownFiles) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains('FIR-')), reason: file.path);
      expect(text, isNot(legacyTopLevelRoute), reason: file.path);
    }
  });
}
