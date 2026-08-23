import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/contracts/source_identity.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/life_signal.dart';
import '../../features/execution/composition/execution_route_paths.dart';
import '../../features/execution/data/providers.dart';
import '../../features/execution/domain/execution_models.dart';

const _actionFamily = 'exec:execution_actions';

DomainLifeSignalSlice executionLifeSignals(Ref ref, DateTime now) {
  final events = <LifeEvent>[];
  final evaluated = <String>{};
  final today = ref.watch(executionTodayActionsProvider).value;
  final open = ref.watch(executionOpenActionsProvider).value ?? today;
  if (open != null) {
    evaluated.add(_actionFamily);
    final blocked = open
        .where((action) => action.status == ExecutionActionStatus.blocked)
        .toList(growable: false);
    if (blocked.isNotEmpty) {
      events.add(
        LifeEvent(
          id: 'sig-exec-blocked',
          at: now,
          domain: DomainScope.execution,
          template: LifeEventTemplate.executionBlocked,
          params: <String>['${blocked.length}'],
          routePath: ExecutionRoutes.today,
          priority: LifeSignalPriority.high,
          evidence: <SourceIdentity>[
            for (final action in blocked.take(8))
              SourceIdentity(
                domain: DomainScope.execution,
                rowFamily: _actionFamily,
                rowId: action.id,
                fingerprint: action.sync.hlc.toString(),
              ),
          ],
        ),
      );
    }
    final due = open
        .where((action) => action.isDue(now))
        .toList(growable: false);
    if (due.isNotEmpty) {
      events.add(
        LifeEvent(
          id: 'sig-exec-due',
          at: now,
          domain: DomainScope.execution,
          template: LifeEventTemplate.executionDue,
          params: <String>['${due.length}'],
          routePath: ExecutionRoutes.today,
          priority: LifeSignalPriority.high,
          evidence: <SourceIdentity>[
            for (final action in due.take(8))
              SourceIdentity(
                domain: DomainScope.execution,
                rowFamily: _actionFamily,
                rowId: action.id,
                fingerprint: action.sync.hlc.toString(),
              ),
          ],
        ),
      );
    }
  }

  return DomainLifeSignalSlice(
    events: List<LifeEvent>.unmodifiable(events),
    evaluatedSourceFamilies: Set<String>.unmodifiable(evaluated),
  );
}

String? executionSourceRouteContribution(String family, String rowId) =>
    switch (family) {
      'exec:execution_actions' => ExecutionRoutes.action(rowId),
      'exec:execution_projects' => ExecutionRoutes.project(rowId),
      'exec:execution_commitments' => ExecutionRoutes.commitment(rowId),
      'exec:execution_progress_entries' => ExecutionRoutes.review,
      _ => null,
    };
