import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth;
import '../../../core/persistence/providers.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/outbox_provider.dart';
import '../domain/health_meal.dart';
import 'health_meal_repository.dart';
import 'health_series_providers.dart';

bool healthMealsEnabled(Ref ref) =>
    ref.read(auth.domainOptInsProvider).value?.contains(DomainScope.health) ??
    false;

final healthMealRepositoryProvider = FutureProvider<HealthMealRepository>((
  ref,
) async {
  final dbFuture = ref.watch(appDatabaseProvider.future);
  final outboxFuture = ref.watch(outboxStoreProvider.future);
  final stamperFuture = ref.watch(mutationStamperProvider.future);
  final clock = ref.watch(healthClockProvider);
  return HealthMealRepository(
    db: await dbFuture,
    outbox: await outboxFuture,
    stamper: await stamperFuture,
    clock: clock,
    writesAllowed: (owner) =>
        healthMealsEnabled(ref) && ref.read(activeUserIdProvider) == owner,
  );
});

final healthMealsProvider = StreamProvider.autoDispose
    .family<List<HealthMeal>, DateTime>((ref, day) async* {
      ref.watch(activeUserIdProvider);
      final optIns = ref.watch(auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) {
        yield const [];
        return;
      }
      final ownerFuture = ref.watch(currentUserIdProvider)();
      final repoFuture = ref.watch(healthMealRepositoryProvider.future);
      final date = DateTime.utc(day.year, day.month, day.day);
      yield* (await repoFuture).watchInRange(
        ownerUserId: await ownerFuture,
        from: date,
        to: date.add(const Duration(days: 1)),
      );
    });

/// Photos are device-local. A synced meal may legitimately have no thumbnail.
/// Revision is part of the key so photo edits reload after the meal is saved.
final healthMealPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List?, ({String id, String revision})>((ref, meal) async {
      final owner = ref.watch(activeUserIdProvider);
      final optIns = ref.watch(auth.domainOptInsProvider).value;
      if (owner == null || !(optIns?.contains(DomainScope.health) ?? false)) {
        return null;
      }
      final repo = await ref.watch(healthMealRepositoryProvider.future);
      return repo.photo(id: meal.id, ownerUserId: owner);
    });
