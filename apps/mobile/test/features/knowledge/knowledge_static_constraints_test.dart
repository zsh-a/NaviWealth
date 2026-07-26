import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final knowledgeFiles = Directory('lib/features/knowledge')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  group('KnowledgeOS static UI constraints', () {
    test('does not import or use Material-only affordances', () {
      // Word-boundary patterns so the sanctioned design-system wrappers
      // (AppRefreshIndicator, OptionalHero) don't trip the ban.
      final forbidden = <RegExp>[
        RegExp(r'package:flutter/material\.dart'),
        RegExp(r'\bRefreshIndicator\('),
        RegExp(r'\bReorderableListView\b'),
        RegExp(r'\bFloatingActionButton\b'),
        RegExp(r'\bHero\('),
      ];

      final offenders = <String>[];
      for (final file in knowledgeFiles) {
        final text = file.readAsStringSync();
        for (final pattern in forbidden) {
          if (pattern.hasMatch(text)) {
            offenders.add('${file.path}: ${pattern.pattern}');
          }
        }
      }

      expect(offenders, isEmpty);
    });

    test('does not reintroduce date substring hacks', () {
      final forbidden = <RegExp>[
        RegExp(r'toIso8601String\(\)\.substring'),
        RegExp(r'substring\(0,\s*10\)'),
        RegExp(r'ts\.substring'),
      ];

      final offenders = <String>[];
      for (final file in knowledgeFiles) {
        final text = file.readAsStringSync();
        for (final pattern in forbidden) {
          if (pattern.hasMatch(text)) {
            offenders.add('${file.path}: ${pattern.pattern}');
          }
        }
      }

      expect(offenders, isEmpty);
    });

    test('does not reintroduce hard-coded display truncation', () {
      final hardCodedHeadSubstring = RegExp(r'substring\(0,\s*\d+\)');
      final offenders = <String>[];
      for (final file in knowledgeFiles) {
        final path = file.path;
        if (path.endsWith('/domain/knowledge_text.dart')) continue;
        final text = file.readAsStringSync();
        if (hardCodedHeadSubstring.hasMatch(text)) {
          offenders.add('$path: substring(0, number)');
        }
      }

      expect(offenders, isEmpty);
    });

    test('keeps empty/error states and card chrome centralized', () {
      final offenders = <String>[];
      for (final file in knowledgeFiles) {
        final text = file.readAsStringSync();
        final path = file.path;
        if (!path.contains('/ui/')) continue;

        if (RegExp(
          r'Center\s*\(\s*child:\s*Text\s*\(',
          multiLine: true,
        ).hasMatch(text)) {
          offenders.add('$path: bare Center(child: Text(...))');
        }
        if (text.contains('_ErrorState')) {
          offenders.add('$path: legacy _ErrorState');
        }
        if (!_isCentralKnowledgeWidgetsFile(path) &&
            text.contains('AppEmptyState')) {
          offenders.add('$path: direct AppEmptyState');
        }
        if (!_isCentralKnowledgeWidgetsFile(path) &&
            text.contains('SoftCard(')) {
          offenders.add('$path: direct SoftCard');
        }
      }

      expect(offenders, isEmpty);
    });

    test('keeps command palette and proposal kind labels localized', () {
      final localizedPresentationFiles = <File>[
        File('lib/core/command_palette/default_commands.dart'),
        File(
          'lib/features/knowledge/composition/knowledge_command_palette.dart',
        ),
        File(
          'lib/features/knowledge/composition/knowledge_proposal_kinds.dart',
        ),
      ];
      final han = RegExp(r'[\u4e00-\u9fff]');
      final offenders = <String>[];
      for (final file in localizedPresentationFiles) {
        final text = file.readAsStringSync();
        if (han.hasMatch(text)) {
          offenders.add('${file.path}: contains Han literal');
        }
        if (text.contains('Labels stay literal') ||
            text.contains('not yet localised') ||
            RegExp(r"label:\s*'").hasMatch(text)) {
          offenders.add('${file.path}: non-localized presentation label');
        }
      }

      expect(offenders, isEmpty);
    });
  });
}

bool _isCentralKnowledgeWidgetsFile(String path) {
  if (path.endsWith('/_widgets.dart')) return true;
  return RegExp(r'/ui/knowledge_[a-z_]+_widgets\.dart$').hasMatch(path);
}
