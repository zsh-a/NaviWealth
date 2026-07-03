part of 'providers.dart';

final _currentOwnerUserIdProvider = FutureProvider<String>((ref) async {
  final stamper = await ref.watch(mutationStamperProvider.future);
  return stamper.currentUserId();
});

final corporateActionRepositoryProvider =
    FutureProvider<CorporateActionRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = await ref.watch(outboxStoreProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return CorporateActionRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
    });

final recordedCorporateActionsProvider =
    StreamProvider.autoDispose<List<CorporateAction>>((ref) async* {
      final repo = await ref.watch(corporateActionRepositoryProvider.future);
      final ownerUserId = await ref.watch(_currentOwnerUserIdProvider.future);
      yield* repo.watchDeclared(ownerUserId);
    });
