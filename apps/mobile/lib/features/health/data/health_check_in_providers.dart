import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth;
import '../../../core/persistence/providers.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/outbox_provider.dart';
import '../domain/health_check_in.dart';
import 'health_check_in_repository.dart';
import 'health_series.dart';
import 'health_series_providers.dart';

final healthCheckInRepositoryProvider = FutureProvider<HealthCheckInRepository>(
  (ref) async {
    final dbFuture = ref.watch(appDatabaseProvider.future);
    final outboxFuture = ref.watch(outboxStoreProvider.future);
    final stamperFuture = ref.watch(mutationStamperProvider.future);
    final clock = ref.watch(healthClockProvider);
    final db = await dbFuture;
    final outbox = await outboxFuture;
    final stamper = await stamperFuture;
    return HealthCheckInRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      clock: clock,
    );
  },
);

final healthCheckInsProvider = StreamProvider.autoDispose
    .family<List<HealthCheckIn>, int>((ref, days) async* {
      ref.watch(activeUserIdProvider);
      if (!(ref
              .watch(auth.domainOptInsProvider)
              .value
              ?.contains(DomainScope.health) ??
          false)) {
        yield const [];
        return;
      }
      ref.watch(healthCalendarDayProvider);
      final ownerFuture = ref.watch(currentUserIdProvider)();
      final repoFuture = ref.watch(healthCheckInRepositoryProvider.future);
      final window = HealthWindow(
        now: ref.watch(healthClockProvider)(),
        days: days,
      );
      final owner = await ownerFuture;
      final repo = await repoFuture;
      yield* repo.watchInRange(
        ownerUserId: owner,
        from: window.start,
        to: window.end,
      );
    });
