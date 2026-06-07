import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_search_suggestions.dart';

void main() {
  group('knowledgeSearchCandidatePhrases', () {
    test('extracts sentence phrases and useful tokens', () {
      final out = knowledgeSearchCandidatePhrases(
        'QQQ vs BOXX rebalance; 港卡需要定期活跃交易',
      );

      expect(out, contains('QQQ vs BOXX rebalance'));
      expect(out, contains('QQQ'));
      expect(out, contains('BOXX'));
      expect(out, contains('rebalance'));
      expect(out, contains('港卡需要定期活跃交易'));
    });
  });

  group('rankKnowledgeSearchSuggestions', () {
    test('prefix matches outrank later substring matches', () {
      final out = rankKnowledgeSearchSuggestions(
        weightedSuggestions: const ['box spread', 'cash box'],
        searchableTexts: const [],
        query: 'box',
      );

      expect(out.take(2), <String>['box spread', 'cash box']);
    });

    test('weighted suggestions outrank body-derived phrases', () {
      final out = rankKnowledgeSearchSuggestions(
        weightedSuggestions: const ['scope:fire'],
        searchableTexts: const ['fire decision rationale'],
        query: 'fire',
      );

      expect(out.first, 'scope:fire');
      expect(out, contains('fire decision rationale'));
    });

    test('duplicates boost repeated candidates without duplicating output', () {
      final out = rankKnowledgeSearchSuggestions(
        weightedSuggestions: const ['港卡', '港卡'],
        searchableTexts: const ['港卡 活跃', '港卡 交易'],
        query: '港',
      );

      expect(out.where((value) => value == '港卡'), hasLength(1));
      expect(out.first, '港卡');
    });
  });
}
