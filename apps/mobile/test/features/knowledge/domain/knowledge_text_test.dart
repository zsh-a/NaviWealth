import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_text.dart';

void main() {
  group('knowledgePlainText', () {
    test('strips headings, emphasis, and list markers', () {
      const raw = '''
## Title
**bold** and *em*
- one
- two
''';
      final plain = knowledgePlainText(raw);
      expect(plain, isNot(contains('##')));
      expect(plain, isNot(contains('**')));
      expect(plain, isNot(contains('- one')));
      expect(plain, contains('Title'));
      expect(plain, contains('bold'));
      expect(plain, contains('em'));
      expect(plain, contains('one'));
    });

    test('turns links into labels and drops image urls', () {
      final plain = knowledgePlainText(
        'see [docs](https://example.com) and ![chart](https://x/y.png)',
      );
      expect(plain, contains('docs'));
      expect(plain, isNot(contains('https://example.com')));
      expect(plain, contains('chart'));
      expect(plain, isNot(contains('https://x/y.png')));
    });

    test('keeps fenced code content without fences', () {
      final plain = knowledgePlainText('```dart\nint x = 1;\n```');
      expect(plain, contains('int x = 1;'));
      expect(plain, isNot(contains('```')));
    });

    test('strips task list checkboxes', () {
      final plain = knowledgePlainText('- [ ] todo\n- [x] done');
      expect(plain, contains('todo'));
      expect(plain, contains('done'));
      expect(plain, isNot(contains('[ ]')));
      expect(plain, isNot(contains('[x]')));
    });
  });

  group('knowledgeExcerpt', () {
    test('strips markdown before truncating', () {
      final excerpt = knowledgeExcerpt(
        '## Heading\n\n**Important** body text that goes on.',
        max: 40,
      );
      expect(excerpt, isNot(contains('##')));
      expect(excerpt, isNot(contains('**')));
      expect(excerpt, contains('Heading'));
      expect(excerpt, contains('Important'));
    });

    test('returns empty for blank or marker-only input', () {
      expect(knowledgeExcerpt('   '), isEmpty);
      expect(knowledgeExcerpt('###   '), isEmpty);
    });

    test('adds ellipsis when over budget', () {
      final long = List.filled(50, 'word').join(' ');
      final excerpt = knowledgeExcerpt(long, max: 20);
      expect(excerpt.endsWith('…'), isTrue);
      expect(excerpt.length, lessThanOrEqualTo(21));
    });
  });
}
