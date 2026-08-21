import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_share_intent_handler.dart';

void main() {
  test('shared URL title favors a readable host and path label', () {
    expect(
      knowledgeSharedUrlTitle(
        'https://www.example.com/articles/decision-memory?ref=share',
      ),
      'example.com · decision-memory',
    );
  });

  test('shared URL title falls back safely for non-URLs', () {
    expect(knowledgeSharedUrlTitle('not a url'), 'not a url');
  });
}
