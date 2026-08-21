import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

Future<void> showKnowledgeRelationSheet(
  BuildContext context,
  WidgetRef _,
  Object item,
) async {
  final source = _RelationTarget.from(item);
  if (source == null) return;
  await showAppSheet<void>(
    context: context,
    title: AppLocalizations.of(context).knowledgeRelationSheetTitle,
    builder: (_) => _KnowledgeRelationSheet(source: source),
  );
}

class _KnowledgeRelationSheet extends ConsumerStatefulWidget {
  const _KnowledgeRelationSheet({required this.source});

  final _RelationTarget source;

  @override
  ConsumerState<_KnowledgeRelationSheet> createState() =>
      _KnowledgeRelationSheetState();
}

class _KnowledgeRelationSheetState
    extends ConsumerState<_KnowledgeRelationSheet> {
  late final Future<List<_RelationTarget>> _targets = _loadTargets();
  final _search = TextEditingController();
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<List<_RelationTarget>> _loadTargets() async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final owner = widget.source.ownerUserId;
    final relations = await repo.listRelationsForObject(
      ownerUserId: owner,
      kind: widget.source.kind,
      id: widget.source.id,
    );
    final linked = <String>{
      for (final relation in relations)
        relation.fromKind == widget.source.kind &&
                relation.fromId == widget.source.id
            ? '${relation.toKind}:${relation.toId}'
            : '${relation.fromKind}:${relation.fromId}',
    };
    final targets =
        <_RelationTarget>[
          for (final value in await repo.listNotes(ownerUserId: owner))
            _RelationTarget.from(value)!,
          for (final value in await repo.listPrinciples(ownerUserId: owner))
            _RelationTarget.from(value)!,
          for (final value in await repo.listAssumptions(ownerUserId: owner))
            _RelationTarget.from(value)!,
          for (final value in await repo.listDecisions(ownerUserId: owner))
            _RelationTarget.from(value)!,
          for (final value in await repo.listConcepts(ownerUserId: owner))
            _RelationTarget.from(value)!,
          for (final value in await repo.listExperiments(ownerUserId: owner))
            _RelationTarget.from(value)!,
          for (final value in await repo.listRoutines(ownerUserId: owner))
            _RelationTarget.from(value)!,
        ]..removeWhere(
          (target) =>
              target.key == widget.source.key || linked.contains(target.key),
        );
    targets.sort(
      (left, right) =>
          left.title.toLowerCase().compareTo(right.title.toLowerCase()),
    );
    return targets;
  }

  Future<void> _link(_RelationTarget target) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = target.key);
    final l10n = AppLocalizations.of(context);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final relation = KnowledgeRelation(
        id: knowledgeRelationId(
          fromKind: widget.source.kind,
          fromId: widget.source.id,
          relation: KnowledgeRelationType.relatedTo,
          toKind: target.kind,
          toId: target.id,
        ),
        fromKind: widget.source.kind,
        fromId: widget.source.id,
        relation: KnowledgeRelationType.relatedTo,
        toKind: target.kind,
        toId: target.id,
        createdAt: stamp.now,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await repo.upsertRelation(relation);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeRelationLinkedToast(target.title),
      );
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<_RelationTarget>>(
      future: _targets,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppEmptyState.inline(
            icon: FLucideIcons.circleX,
            title: l10n.commonLoadFailed,
            tone: AppEmptyStateTone.error,
          );
        }
        if (!snapshot.hasData) return const Center(child: FCircularProgress());
        final query = _search.text.trim().toLowerCase();
        final targets = snapshot.data!
            .where(
              (target) =>
                  query.isEmpty ||
                  target.title.toLowerCase().contains(query) ||
                  target.kind.toLowerCase().contains(query),
            )
            .take(100)
            .toList(growable: false);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                AppSpacing.s4,
                AppSpacing.s16,
                AppSpacing.s12,
              ),
              child: FTextField(
                control: FTextFieldControl.managed(controller: _search),
                hint: l10n.knowledgeRelationSearchHint,
                prefixBuilder: (context, style, variants) =>
                    FTextField.prefixIconBuilder(
                      context,
                      style,
                      variants,
                      const Icon(FLucideIcons.search),
                    ),
              ),
            ),
            if (targets.isEmpty)
              Padding(
                padding: AppPageRhythm.densePadding,
                child: AppEmptyState.inline(
                  icon: FLucideIcons.link,
                  title: query.isEmpty
                      ? l10n.knowledgeRelationNoTargets
                      : l10n.knowledgeLibrarySearchEmptyTitle,
                ),
              )
            else
              AppActionSheetList(
                children: [
                  for (final target in targets)
                    AppActionSheetTile(
                      icon: target.icon,
                      title: target.title,
                      subtitle: target.kindLabel(l10n),
                      showChevron: false,
                      onPress: () {
                        if (_busyKey == null) _link(target);
                      },
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _RelationTarget {
  const _RelationTarget({
    required this.id,
    required this.kind,
    required this.title,
    required this.ownerUserId,
    required this.icon,
  });

  final String id;
  final String kind;
  final String title;
  final String ownerUserId;
  final IconData icon;

  String get key => '$kind:$id';

  String kindLabel(AppLocalizations l10n) => switch (kind) {
    'note' => l10n.knowledgeSegmentNotes,
    'principle' => l10n.knowledgeSegmentPrinciples,
    'assumption' => l10n.knowledgeSegmentAssumptions,
    'decision' => l10n.knowledgeSegmentDecisions,
    'concept' => l10n.knowledgeSegmentConcepts,
    'experiment' => l10n.knowledgeSegmentExperiments,
    'routine' => l10n.knowledgeSegmentRoutines,
    _ => kind,
  };

  static _RelationTarget? from(Object value) => switch (value) {
    KnowledgeNote item => _RelationTarget(
      id: item.id,
      kind: 'note',
      title: item.title,
      ownerUserId: item.sync.ownerUserId,
      icon: FLucideIcons.fileText,
    ),
    KnowledgePrinciple item => _RelationTarget(
      id: item.id,
      kind: 'principle',
      title: item.statement,
      ownerUserId: item.sync.ownerUserId,
      icon: FLucideIcons.lightbulb,
    ),
    KnowledgeAssumption item => _RelationTarget(
      id: item.id,
      kind: 'assumption',
      title: item.statement,
      ownerUserId: item.sync.ownerUserId,
      icon: FLucideIcons.badgeCheck,
    ),
    KnowledgeDecision item => _RelationTarget(
      id: item.id,
      kind: 'decision',
      title: item.question,
      ownerUserId: item.sync.ownerUserId,
      icon: FLucideIcons.gitBranch,
    ),
    KnowledgeConcept item => _RelationTarget(
      id: item.id,
      kind: 'concept',
      title: item.name,
      ownerUserId: item.sync.ownerUserId,
      icon: FLucideIcons.folderTree,
    ),
    KnowledgeExperiment item => _RelationTarget(
      id: item.id,
      kind: 'experiment',
      title: item.hypothesis,
      ownerUserId: item.sync.ownerUserId,
      icon: FLucideIcons.flaskConical,
    ),
    KnowledgeRoutine item => _RelationTarget(
      id: item.id,
      kind: 'routine',
      title: item.statement,
      ownerUserId: item.sync.ownerUserId,
      icon: FLucideIcons.calendarClock,
    ),
    _ => null,
  };
}
