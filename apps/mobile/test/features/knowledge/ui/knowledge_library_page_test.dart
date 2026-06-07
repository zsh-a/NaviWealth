import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_library_page.dart';

void main() {
  group('matchesKnowledgeLibraryDateFilter', () {
    test('matches day-distance buckets for past and future dates', () {
      final now = DateTime.utc(2026, 6, 7, 12);

      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 6, 7, 1),
          KnowledgeLibraryDateFilter.today,
          now,
        ),
        isTrue,
      );
      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 6, 1),
          KnowledgeLibraryDateFilter.week,
          now,
        ),
        isTrue,
      );
      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 5, 8),
          KnowledgeLibraryDateFilter.month,
          now,
        ),
        isTrue,
      );
      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 7, 15),
          KnowledgeLibraryDateFilter.outsideMonth,
          now,
        ),
        isTrue,
      );
    });

    test('excludes dates outside the selected bucket', () {
      final now = DateTime.utc(2026, 6, 7, 12);

      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 6, 8),
          KnowledgeLibraryDateFilter.today,
          now,
        ),
        isFalse,
      );
      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 6, 16),
          KnowledgeLibraryDateFilter.week,
          now,
        ),
        isFalse,
      );
      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 7, 8),
          KnowledgeLibraryDateFilter.month,
          now,
        ),
        isFalse,
      );
    });
  });
}
