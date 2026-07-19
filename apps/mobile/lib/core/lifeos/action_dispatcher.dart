import 'package:flutter_riverpod/flutter_riverpod.dart';

final class LifeActionDraft {
  const LifeActionDraft({
    required this.title,
    required this.note,
    required this.sourceDomain,
    required this.sourceRowFamily,
    required this.sourceRowId,
    this.dueAt,
    this.priority = 'normal',
  });

  final String title;
  final String note;
  final String sourceDomain;
  final String sourceRowFamily;
  final String sourceRowId;
  final DateTime? dueAt;
  final String priority;
}

typedef LifeActionDispatcher = Future<String?> Function(LifeActionDraft draft);

/// App-composition seam for creating an Execution action without making a
/// source domain import ExecutionOS.
final lifeActionDispatcherProvider = Provider<LifeActionDispatcher>(
  (ref) =>
      (draft) async => null,
);

final lifeActionReviewRouteProvider = Provider<String?>((ref) => null);
