import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth;
import '../domain/health_metric_kind.dart';
import 'health_calendar_providers.dart';
import 'health_preferences.dart';
import 'health_series.dart';
import 'providers.dart';

export 'health_calendar_providers.dart'
    show healthClockProvider, healthCalendarDayProvider;

final healthTrendSeriesProvider = FutureProvider.autoDispose
    .family<
      Map<HealthMetricKind, HealthSeries>,
      ({TrendGroup group, int windowDays})
    >((ref, params) async {
      final enabled =
          ref
              .watch(auth.domainOptInsProvider)
              .value
              ?.contains(DomainScope.health) ??
          false;
      ref.watch(activeUserIdProvider);
      if (!enabled) return const {};
      ref.watch(healthCalendarDayProvider);
      final ownerFuture = ref.watch(currentUserIdProvider)();
      final preferencesFuture = ref.watch(healthPreferencesProvider.future);
      final repoFuture = ref.watch(healthMetricRepositoryProvider.future);
      final window = HealthWindow(
        now: ref.watch(healthClockProvider)(),
        days: params.windowDays,
      );
      final kinds = HealthMetricKind.values
          .where(
            (k) => k != HealthMetricKind.unknown && k.group == params.group,
          )
          .toSet();
      final owner = await ownerFuture;
      final preferences = await preferencesFuture;
      final repo = await repoFuture;
      // Include timezone edges and overnight session starts; the projector applies
      // the exact calendar bounds after source selection and wake-date attribution.
      final rows = await repo.listInRange(
        ownerUserId: owner,
        kinds: kinds,
        from: window.previous.start.subtract(const Duration(days: 2)),
        to: window.end.add(const Duration(days: 2)),
      );
      return {
        for (final kind in kinds)
          kind: buildHealthSeries(
            kind: kind,
            rows: rows[kind] ?? [],
            window: window,
            preferredSource: preferences.sources[kind],
          ),
      };
    });
