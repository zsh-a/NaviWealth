import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../domain/approved_underlying.dart';
import '../domain/options_strategy_profile.dart';
import 'approved_underlyings_repository.dart';
import 'options_strategy_profile_repository.dart';

final optionsStrategyProfileRepositoryProvider =
    FutureProvider<OptionsStrategyProfileRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return OptionsStrategyProfileRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
  );
});

final approvedUnderlyingsRepositoryProvider =
    FutureProvider<ApprovedUnderlyingsRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return ApprovedUnderlyingsRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
  );
});

/// Streams the current user's [OptionsStrategyProfile], `null` when the
/// user hasn't configured one yet (first run).
final optionsStrategyProfileProvider =
    StreamProvider.autoDispose<OptionsStrategyProfile?>((ref) async* {
  final repo = await ref.watch(optionsStrategyProfileRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  yield* repo.watch(ownerUserId);
});

/// Streams the user's approved underlyings list (alphabetic by symbol).
final approvedUnderlyingsProvider =
    StreamProvider.autoDispose<List<ApprovedUnderlying>>((ref) async* {
  final repo = await ref.watch(approvedUnderlyingsRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  yield* repo.watchActive(ownerUserId);
});
