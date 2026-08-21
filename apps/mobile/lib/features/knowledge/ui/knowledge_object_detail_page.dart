/// KnowledgeOS read-only detail page for the non-Decision typed objects
/// (`docs/domains/knowledgeos-domain.md` §3 — Note / Concept / Experiment /
/// Principle / Assumption / Routine).
///
/// Decision has its own editable page; these objects share one read view
/// keyed by `:kind` so every Library tile is tappable (the interaction
/// asymmetry called out in the 2026-05-29 audit). Loading is by id via
/// the repository `findX` accessors, so a referenced-but-archived row
/// still resolves.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/knowledge_llm_client.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_object_writers.dart';
import '_routine_writer.dart';
import '_widgets.dart';
import 'knowledge_execution_action.dart';
import 'knowledge_item_actions.dart';
import 'knowledge_status_labels.dart';

part 'knowledge_object_detail_links.dart';
part 'knowledge_object_detail_sections.dart';

/// The kinds this page can render. Mirrors the `:kind` path segment.
enum KnowledgeObjectKind {
  note,
  concept,
  experiment,
  principle,
  assumption,
  routine;

  static KnowledgeObjectKind? parse(String? s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

class KnowledgeObjectDetailPage extends ConsumerStatefulWidget {
  const KnowledgeObjectDetailPage({
    super.key,
    required this.kind,
    required this.id,
  });
  final String kind;
  final String id;

  @override
  ConsumerState<KnowledgeObjectDetailPage> createState() =>
      _KnowledgeObjectDetailPageState();
}

class _KnowledgeObjectDetailPageState
    extends ConsumerState<KnowledgeObjectDetailPage> {
  Object? _object;
  Object? _error;
  List<KnowledgeConcept> _relatedConcepts = const <KnowledgeConcept>[];
  KnowledgeAssumption? _targetAssumption;
  List<KnowledgeNote> _evidenceNotes = const <KnowledgeNote>[];
  List<KnowledgeDecision> _referencingDecisions = const <KnowledgeDecision>[];
  List<KnowledgeDecision> _linkedDecisions = const <KnowledgeDecision>[];
  List<KnowledgeExperiment> _targetingExperiments =
      const <KnowledgeExperiment>[];
  bool _loading = true;
  int _loadGeneration = 0;

  KnowledgeObjectKind? get _kind => KnowledgeObjectKind.parse(widget.kind);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KnowledgeObjectDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind || oldWidget.id != widget.id) {
      _object = null;
      _relatedConcepts = const <KnowledgeConcept>[];
      _targetAssumption = null;
      _evidenceNotes = const <KnowledgeNote>[];
      _referencingDecisions = const <KnowledgeDecision>[];
      _linkedDecisions = const <KnowledgeDecision>[];
      _targetingExperiments = const <KnowledgeExperiment>[];
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    final kind = _kind;
    if (kind == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final ownerUserId = await ref.read(knowledgeOwnerUserIdProvider.future);
      final obj = await _fetch(repo, ownerUserId, kind, widget.id);
      final related = await _fetchRelated(repo, obj);
      final linkedDecisions = await _fetchLinkedDecisions(
        repo,
        ownerUserId,
        kind,
        widget.id,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _object = obj;
          _relatedConcepts = related.relatedConcepts;
          _targetAssumption = related.targetAssumption;
          _evidenceNotes = related.evidenceNotes;
          _referencingDecisions = related.referencingDecisions;
          final referencedIds = related.referencingDecisions
              .map((decision) => decision.id)
              .toSet();
          _linkedDecisions = linkedDecisions
              .where((decision) => !referencedIds.contains(decision.id))
              .toList(growable: false);
          _targetingExperiments = related.targetingExperiments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<List<KnowledgeDecision>> _fetchLinkedDecisions(
    KnowledgeRepository repo,
    String ownerUserId,
    KnowledgeObjectKind kind,
    String id,
  ) async {
    final relations = await repo.listRelationsFrom(
      ownerUserId: ownerUserId,
      fromKind: kind.name,
      fromId: id,
    );
    final decisions = <KnowledgeDecision>[];
    for (final relation in relations) {
      if (relation.toKind != KnowledgeEntryKind.decision.name) continue;
      final decision = await repo.findDecision(
        ownerUserId: ownerUserId,
        id: relation.toId,
      );
      if (decision != null) decisions.add(decision);
    }
    return decisions;
  }

  Future<Object?> _fetch(
    KnowledgeRepository repo,
    String ownerUserId,
    KnowledgeObjectKind kind,
    String id,
  ) {
    return switch (kind) {
      KnowledgeObjectKind.note => repo.findNote(
        ownerUserId: ownerUserId,
        id: id,
      ),
      KnowledgeObjectKind.concept => repo.findConcept(
        ownerUserId: ownerUserId,
        id: id,
      ),
      KnowledgeObjectKind.experiment => repo.findExperiment(
        ownerUserId: ownerUserId,
        id: id,
      ),
      KnowledgeObjectKind.principle => repo.findPrinciple(
        ownerUserId: ownerUserId,
        id: id,
      ),
      KnowledgeObjectKind.assumption => repo.findAssumption(
        ownerUserId: ownerUserId,
        id: id,
      ),
      KnowledgeObjectKind.routine => repo.findRoutine(
        ownerUserId: ownerUserId,
        id: id,
      ),
    };
  }

  Future<_ObjectRelatedData> _fetchRelated(
    KnowledgeRepository repo,
    Object? obj,
  ) async {
    if (obj == null) return const _ObjectRelatedData();
    switch (obj) {
      case final KnowledgeConcept c:
        final related = <KnowledgeConcept>[];
        for (final id in c.relatedConceptIds) {
          final concept = await repo.findConcept(
            ownerUserId: c.sync.ownerUserId,
            id: id,
          );
          if (concept != null) related.add(concept);
        }
        return _ObjectRelatedData(relatedConcepts: related);
      case final KnowledgeExperiment e:
        final targetId = e.targetAssumptionId;
        if (targetId == null || targetId.isEmpty) {
          return const _ObjectRelatedData();
        }
        return _ObjectRelatedData(
          targetAssumption: await repo.findAssumption(
            ownerUserId: e.sync.ownerUserId,
            id: targetId,
          ),
        );
      case final KnowledgePrinciple p:
        final decisions = await repo.listDecisions(
          ownerUserId: p.sync.ownerUserId,
          limit: 1000,
        );
        return _ObjectRelatedData(
          referencingDecisions: decisions
              .where((d) => d.principleIds.contains(p.id))
              .toList(growable: false),
        );
      case final KnowledgeAssumption a:
        final notes = <KnowledgeNote>[];
        for (final id in a.evidenceIds) {
          final note = await repo.findNote(
            ownerUserId: a.sync.ownerUserId,
            id: id,
          );
          if (note != null) notes.add(note);
        }
        final decisions = await repo.listDecisions(
          ownerUserId: a.sync.ownerUserId,
          limit: 1000,
        );
        final experiments = await repo.listExperiments(
          ownerUserId: a.sync.ownerUserId,
          limit: 1000,
        );
        return _ObjectRelatedData(
          evidenceNotes: notes,
          referencingDecisions: decisions
              .where((d) => d.assumptionIds.contains(a.id))
              .toList(growable: false),
          targetingExperiments: experiments
              .where((e) => e.targetAssumptionId == a.id)
              .toList(growable: false),
        );
    }
    return const _ObjectRelatedData();
  }

  @override
  Widget build(BuildContext context) {
    final obj = _object;
    final moreActions = obj == null
        ? const <AppAdaptiveAction>[]
        : knowledgeItemActions(
            context: context,
            ref: ref,
            item: obj,
            aiAvailable: ref.watch(knowledgeLlmProfileClientProvider) != null,
            includeEditInMenu: false,
          ).menuActions;
    return ObjectDetailScaffold(
      title: _title(context),
      actions: [
        if (_canEdit)
          AppHeaderAction(
            semanticsLabel: AppLocalizations.of(context).knowledgeMarkdownEdit,
            icon: const Icon(FLucideIcons.pencil),
            onPress: () => _editObject(context),
          ),
        if (moreActions.isNotEmpty)
          AppAdaptiveActionMenu(
            title: AppLocalizations.of(context).knowledgeLibraryItemActions,
            actions: [
              for (final action in moreActions)
                AppAdaptiveAction(
                  icon: action.icon,
                  title: action.title,
                  subtitle: action.subtitle,
                  destructive: action.destructive,
                  onPress: () async {
                    await action.onPress();
                    if (mounted) await _load();
                  },
                ),
            ],
            triggerBuilder: (context, openMenu, focusNode) => AppHeaderAction(
              semanticsLabel: AppLocalizations.of(
                context,
              ).knowledgeLibraryItemActions,
              icon: const Icon(FLucideIcons.ellipsis),
              focusNode: focusNode,
              onPress: openMenu,
            ),
          ),
      ],
      child: _buildBody(),
    );
  }

  bool get _canEdit => _object != null && _kind != null;

  Future<void> _editObject(BuildContext context) async {
    final obj = _object;
    if (obj == null) return;
    switch (obj) {
      case final KnowledgeNote n:
        await showEditNoteSheet(context, ref, n);
      case final KnowledgeConcept c:
        await showEditConceptSheet(context, ref, c);
      case final KnowledgePrinciple p:
        await showEditPrincipleSheet(context, ref, p);
      case final KnowledgeAssumption a:
        await showEditAssumptionSheet(context, ref, a);
      case final KnowledgeExperiment e:
        await showEditExperimentSheet(context, ref, e);
      case final KnowledgeRoutine r:
        await showEditRoutineSheet(context, ref, r);
      default:
        return;
    }
    if (mounted) await _load();
  }

  String _title(BuildContext context) => switch (_kind) {
    KnowledgeObjectKind.note => AppLocalizations.of(
      context,
    ).knowledgeNoteDetailTitle,
    KnowledgeObjectKind.concept => AppLocalizations.of(
      context,
    ).knowledgeConceptDetailTitle,
    KnowledgeObjectKind.experiment => AppLocalizations.of(
      context,
    ).knowledgeExperimentDetailTitle,
    KnowledgeObjectKind.principle => AppLocalizations.of(
      context,
    ).knowledgePrincipleDetailTitle,
    KnowledgeObjectKind.assumption => AppLocalizations.of(
      context,
    ).knowledgeAssumptionDetailTitle,
    KnowledgeObjectKind.routine => AppLocalizations.of(
      context,
    ).knowledgeRoutineDetailTitle,
    null => AppLocalizations.of(context).knowledgeObjectDetailTitle,
  };

  Widget _buildBody() {
    if (_loading) return const AppListPageSkeleton(itemCount: 5);
    final error = _error;
    if (error != null) {
      return AppEmptyState.error(
        title: userSafeErrorMessage(
          context,
          error,
          operation: 'load knowledge object',
        ),
        retryLabel: AppLocalizations.of(context).commonRetry,
        onRetry: _load,
      );
    }
    final obj = _object;
    if (obj == null) {
      return AppEmptyState(
        icon: FLucideIcons.fileQuestion,
        title: AppLocalizations.of(context).knowledgeObjectNotFound,
      );
    }
    final children = switch (obj) {
      final KnowledgeNote n => _noteSections(context, n),
      final KnowledgeConcept c => _conceptSections(
        context,
        c,
        relatedConcepts: _relatedConcepts,
      ),
      final KnowledgeExperiment e => _experimentSections(
        context,
        e,
        targetAssumption: _targetAssumption,
      ),
      final KnowledgePrinciple p => _principleSections(
        context,
        p,
        referencingDecisions: _referencingDecisions,
      ),
      final KnowledgeAssumption a => _assumptionSections(
        context,
        a,
        evidenceNotes: _evidenceNotes,
        referencingDecisions: _referencingDecisions,
        targetingExperiments: _targetingExperiments,
      ),
      final KnowledgeRoutine r => _routineSections(context, r),
      _ => const <Widget>[],
    };
    final allSections = <Widget>[...children];
    final executionAction = _executionActionFor(obj);
    if (executionAction != null) allSections.insert(1, executionAction);
    if (_linkedDecisions.isNotEmpty) {
      allSections.addAll(<Widget>[
        const SizedBox(height: AppSpacing.s12),
        _DecisionLinksSection(decisions: _linkedDecisions),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: allSections,
    );
  }

  Widget? _executionActionFor(Object obj) {
    final l10n = AppLocalizations.of(context);
    return switch (obj) {
      final KnowledgeNote note => KnowledgeExecutionAction(
        draftTitle: l10n.knowledgeNoteActionDraftTitle(
          note.title.trim().isEmpty ? l10n.knowledgeUntitled : note.title,
        ),
        draftNote: knowledgeExcerpt(note.bodyMd),
        sourceRowFamily: 'know:knowledge_notes',
        sourceRowId: note.id,
        prompt: l10n.knowledgeNoteActionPrompt,
      ),
      final KnowledgeExperiment experiment
          when experiment.status == ExperimentStatus.planned ||
              experiment.status == ExperimentStatus.running =>
        KnowledgeExecutionAction(
          draftTitle: l10n.knowledgeExperimentActionDraftTitle(
            experiment.hypothesis,
          ),
          draftNote: knowledgeExcerpt(experiment.methodMd),
          sourceRowFamily: 'know:knowledge_experiments',
          sourceRowId: experiment.id,
          prompt: l10n.knowledgeExperimentActionPrompt,
        ),
      _ => null,
    };
  }
}

class _ObjectRelatedData {
  const _ObjectRelatedData({
    this.relatedConcepts = const <KnowledgeConcept>[],
    this.targetAssumption,
    this.evidenceNotes = const <KnowledgeNote>[],
    this.referencingDecisions = const <KnowledgeDecision>[],
    this.targetingExperiments = const <KnowledgeExperiment>[],
  });

  final List<KnowledgeConcept> relatedConcepts;
  final KnowledgeAssumption? targetAssumption;
  final List<KnowledgeNote> evidenceNotes;
  final List<KnowledgeDecision> referencingDecisions;
  final List<KnowledgeExperiment> targetingExperiments;
}
