import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_source_url.dart';

void main() {
  test('normalizes web sources for stable identity', () {
    expect(
      normalizeKnowledgeSourceUrl(
        '  HTTPS://WWW.Example.COM:443/article?id=7#section  ',
      ),
      'https://www.example.com/article?id=7',
    );
    expect(
      normalizeKnowledgeSourceUrl('example.com/guide'),
      'https://example.com/guide',
    );
    expect(
      normalizeKnowledgeSourceUrl('https://example.com/'),
      'https://example.com',
    );
  });

  test('rejects non-web, credentialed, and malformed sources', () {
    expect(normalizeKnowledgeSourceUrl('javascript:alert(1)'), isNull);
    expect(normalizeKnowledgeSourceUrl('ftp://example.com/file'), isNull);
    expect(
      normalizeKnowledgeSourceUrl('https://user:secret@example.com'),
      isNull,
    );
    expect(normalizeKnowledgeSourceUrl('not a source'), isNull);
  });

  test('uses a concise host label', () {
    final uri = parseKnowledgeSourceUrl('https://www.example.com/article');
    expect(uri, isNotNull);
    expect(knowledgeSourceHost(uri!), 'example.com');
  });
}
