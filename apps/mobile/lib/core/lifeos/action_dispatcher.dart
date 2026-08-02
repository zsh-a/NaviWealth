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

enum LifeActionState { todo, doing, blocked, done, dropped }

typedef LifeActionStateReader =
    Future<LifeActionState?> Function(String actionId);

typedef LifeActionSource = ({String rowFamily, String rowId});

final class LifeLinkedAction {
  const LifeLinkedAction({required this.id, required this.state});

  final String id;
  final LifeActionState state;
}

typedef LifeSourceActionReader =
    Future<LifeLinkedAction?> Function(LifeActionSource source);

/// App-composition seam for creating an Execution action without making a
/// source domain import ExecutionOS.
final lifeActionDispatcherProvider = Provider<LifeActionDispatcher>(
  (ref) =>
      (draft) async => null,
);

final lifeActionReviewRouteProvider = Provider<String?>((ref) => null);

/// App-composition seam for opening a concrete Execution action without
/// making the source domain depend on ExecutionOS route contracts.
final lifeActionRouteBuilderProvider =
    Provider<String Function(String actionId)?>((ref) => null);

final lifeActionStateReaderProvider = Provider<LifeActionStateReader>(
  (ref) =>
      (actionId) async => null,
);

final lifeSourceActionReaderProvider = Provider<LifeSourceActionReader>(
  (ref) =>
      (source) async => null,
);

final lifeLinkedActionProvider = FutureProvider.autoDispose
    .family<LifeLinkedAction?, LifeActionSource>((ref, source) {
      return ref.watch(lifeSourceActionReaderProvider)(source);
    });

final lifeActionStateProvider = FutureProvider.autoDispose
    .family<LifeActionState?, String>((ref, actionId) {
      return ref.watch(lifeActionStateReaderProvider)(actionId);
    });

/// Domain-neutral read seam used by review workflows. `null` means the
/// Execution domain is inactive, not that loading failed.
final lifeOpenActionCountProvider = Provider<AsyncValue<int?>>(
  (ref) => const AsyncValue.data(null),
);
