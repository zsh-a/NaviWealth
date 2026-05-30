import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_review_page.dart';

void main() {
  KnowledgeRoutine routine({
    required DateTime nextDueAt,
    DateTime? lastDoneAt,
    int intervalDays = 7,
    RoutineStatus status = RoutineStatus.active,
  }) {
    final created = DateTime.utc(2026, 1, 1);
    return KnowledgeRoutine(
      id: 'routine',
      statement: '每周对账',
      intervalDays: intervalDays,
      nextDueAt: nextDueAt,
      lastDoneAt: lastDoneAt,
      scope: '*',
      status: status,
      createdAt: created,
      sync: SyncMeta(
        ownerUserId: 'u-test',
        updatedAt: created,
        updatedByDevice: 'dev-test',
        hlc: Hlc.zero('dev-test'),
      ),
    );
  }

  group('shouldShowRoutineInReview', () {
    test('shows active routines due within the lookahead window', () {
      final now = DateTime.utc(2026, 5, 30, 10);

      expect(
        shouldShowRoutineInReview(
          routine(nextDueAt: DateTime.utc(2026, 6, 2)),
          now,
        ),
        isTrue,
      );
    });

    test(
      'hides routines completed today even if the next run is this week',
      () {
        final now = DateTime.utc(2026, 5, 30, 10);

        expect(
          shouldShowRoutineInReview(
            routine(
              nextDueAt: DateTime.utc(2026, 6, 6, 10),
              lastDoneAt: DateTime.utc(2026, 5, 30, 9),
            ),
            now,
          ),
          isFalse,
        );
      },
    );

    test('hides inactive or outside-window routines', () {
      final now = DateTime.utc(2026, 5, 30, 10);

      expect(
        shouldShowRoutineInReview(
          routine(
            nextDueAt: DateTime.utc(2026, 6, 1),
            status: RoutineStatus.paused,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        shouldShowRoutineInReview(
          routine(nextDueAt: DateTime.utc(2026, 6, 8)),
          now,
        ),
        isFalse,
      );
    });
  });
}
