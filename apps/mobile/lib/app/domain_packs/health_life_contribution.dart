import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/contracts/source_identity.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/life_signal.dart';
import '../../features/health/composition/health_route_paths.dart';
import '../../features/health/ui/health_today_providers.dart';

const _metricFamily = 'health:health_metrics';

DomainLifeSignalSlice healthLifeSignals(Ref ref, DateTime now) {
  final events = <LifeEvent>[];
  final evaluated = <String>{};
  final recovery = ref.watch(recoverySignalProvider);
  if (_settled(recovery)) evaluated.add(_metricFamily);
  final value = _settled(recovery) ? recovery.value : null;
  final verdict = value?['verdict']?.toString();
  if (verdict == 'strained') {
    events.add(
      LifeEvent(
        id: 'sig-recovery',
        at: now,
        domain: DomainScope.health,
        template: LifeEventTemplate.recoveryAlert,
        params: <String>[verdict!, ?value?['score']?.toString()],
        routePath: HealthRoutes.today,
        priority: LifeSignalPriority.high,
        actionSuggestion: LifeActionSuggestion(
          template: LifeActionTemplate.protectRecovery,
          sourceRowFamily: _metricFamily,
          sourceRowId: 'recovery:${_dayKey(now)}',
        ),
        evidence: <SourceIdentity>[
          SourceIdentity(
            domain: DomainScope.health,
            rowFamily: _metricFamily,
            rowId: 'recovery:${_dayKey(now)}',
            fingerprint: sha256
                .convert(utf8.encode(jsonEncode(value)))
                .toString(),
          ),
        ],
      ),
    );
  }

  return DomainLifeSignalSlice(
    events: List<LifeEvent>.unmodifiable(events),
    evaluatedSourceFamilies: Set<String>.unmodifiable(evaluated),
  );
}

String? healthSourceRoute(String family, String rowId) => switch (family) {
  _metricFamily => HealthRoutes.trend,
  _ => null,
};

bool _settled<T>(AsyncValue<T> value) =>
    value.hasValue && !value.hasError && !value.isLoading;

String _dayKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
