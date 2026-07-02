import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/visual/ai_sparkle.dart';

void main() {
  test('AiSparkle stays small and quiet by default', () {
    const sparkle = AiSparkle();

    expect(sparkle.size, 12);
    expect(sparkle.active, isFalse);
  });

  test('AI surfaces stay within Calm visual primitives', () {
    final violations = <String>[];

    for (final file in _contractFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripLineComment(lines[i]);
        if (code.trim().isEmpty) continue;

        final location = '${file.path}:${i + 1}';
        for (final rule in _rules) {
          if (rule.pattern.hasMatch(code)) {
            violations.add('$location: ${rule.message}');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'AI Calm visual surfaces must use AiSparkle/AiTone primitives: '
          'no filled sparkle glyphs, secondary/tertiary palette shortcuts, '
          'gradients, or shadow glow.',
    );
  });
}

List<File> _contractFiles() {
  final roots = <String>[
    'lib/core/ai/visual',
    'lib/core/ai/write',
    'lib/features/ai_chat',
    'lib/features/finance/ingest',
  ];

  final files = <File>[];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    files.addAll(
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.g.dart'))
          .where((file) => !file.path.endsWith('.freezed.dart')),
    );
  }
  return files..sort((a, b) => a.path.compareTo(b.path));
}

final _rules = <_Rule>[
  _Rule(
    RegExp(r'\bIcons\.auto_awesome\b'),
    'use AiSparkle / outlined sparkles instead of filled Icons.auto_awesome',
  ),
  _Rule(
    RegExp(r'\bcolorScheme\.(?:secondary|tertiary)\b'),
    'use AiTone roles instead of Material secondary/tertiary',
  ),
  _Rule(
    RegExp(r'\b(?:LinearGradient|RadialGradient)\s*\('),
    'AI Calm surfaces must not introduce gradients',
  ),
  _Rule(
    RegExp(r'\bBoxShadow\s*\('),
    'AI Calm surfaces must not introduce shadow glow',
  ),
];

class _Rule {
  const _Rule(this.pattern, this.message);

  final RegExp pattern;
  final String message;
}

String _stripLineComment(String line) {
  final index = line.indexOf('//');
  return index == -1 ? line : line.substring(0, index);
}
