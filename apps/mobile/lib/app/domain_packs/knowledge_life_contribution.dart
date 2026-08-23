import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/contracts/source_identity.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/life_signal.dart';
import '../../features/knowledge/composition/knowledge_route_paths.dart';
import '../../features/knowledge/data/providers.dart';

const _noteFamily = 'know:knowledge_notes';

DomainLifeSignalSlice knowledgeLifeSignals(Ref ref, DateTime now) {
  final events = <LifeEvent>[];
  final evaluated = <String>{};
  final inbox = ref.watch(knowledgeInboxNotesProvider);
  if (_settled(inbox)) evaluated.add(_noteFamily);
  final count = _settled(inbox) ? inbox.value?.length ?? 0 : 0;
  if (count >= 3) {
    events.add(
      LifeEvent(
        id: 'sig-know-inbox',
        at: now,
        domain: DomainScope.knowledge,
        template: LifeEventTemplate.knowledgeInbox,
        params: <String>['$count'],
        routePath: KnowledgeRoutes.inbox,
        actionSuggestion: const LifeActionSuggestion(
          template: LifeActionTemplate.reviewKnowledgeInbox,
          sourceRowFamily: _noteFamily,
          sourceRowId: 'inbox',
        ),
        evidence: <SourceIdentity>[
          for (final note in inbox.value!.take(8))
            SourceIdentity(
              domain: DomainScope.knowledge,
              rowFamily: _noteFamily,
              rowId: note.id,
              fingerprint: note.sync.hlc.toString(),
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

String? knowledgeSourceRoute(String family, String rowId) {
  if (family == _noteFamily && rowId == 'inbox') {
    return KnowledgeRoutes.inbox;
  }
  const kinds = <String, String>{
    'know:knowledge_notes': 'note',
    'know:knowledge_principles': 'principle',
    'know:knowledge_assumptions': 'assumption',
    'know:knowledge_concepts': 'concept',
    'know:knowledge_experiments': 'experiment',
    'know:knowledge_routines': 'routine',
  };
  if (family == 'know:knowledge_decisions') {
    return KnowledgeRoutes.decision(rowId);
  }
  final kind = kinds[family];
  return kind == null ? null : KnowledgeRoutes.object(kind, rowId);
}

bool _settled<T>(AsyncValue<T> value) =>
    value.hasValue && !value.hasError && !value.isLoading;
