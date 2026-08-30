import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/sync_meta.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/knowledge_route_paths.dart';
import '../../data/knowledge_repository.dart';
import '../../data/providers.dart';
import '../../domain/knowledge_models.dart';
import '../../domain/knowledge_text.dart';
import '../knowledge_relation_picker_sheet.dart';

class KnowledgeRelationsSection extends ConsumerWidget {
  const KnowledgeRelationsSection({
    super.key,
    required this.subjectKind,
    required this.subjectId,
    this.onCreateDecision,
  });

  final KnowledgeEntryKind subjectKind;
  final String subjectId;
  final VoidCallback? onCreateDecision;

  KnowledgeRelationSubject get _subject =>
      (kind: subjectKind.name, id: subjectId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final relationsAsync = ref.watch(
      knowledgeRelationsForObjectProvider(_subject),
    );
    final notesAsync = ref.watch(knowledgeNotesProvider);
    final decisionsAsync = ref.watch(knowledgeDecisionsProvider);
    final error =
        relationsAsync.error ?? notesAsync.error ?? decisionsAsync.error;
    final loading =
        (relationsAsync.isLoading && !relationsAsync.hasValue) ||
        (notesAsync.isLoading && !notesAsync.hasValue) ||
        (decisionsAsync.isLoading && !decisionsAsync.hasValue);
    final relations = relationsAsync.value ?? const <KnowledgeRelation>[];
    final items = _resolveItems(
      relations: relations,
      notes: notesAsync.value ?? const <KnowledgeNote>[],
      decisions: decisionsAsync.value ?? const <KnowledgeDecision>[],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.module(
          title: l10n.knowledgeRelationsTitle,
          subtitle: l10n.knowledgeRelationsSubtitle,
          trailing: AppIconButton(
            key: const Key('knowledge-relations-add'),
            icon: FLucideIcons.link2,
            tooltip: l10n.knowledgeRelationAddAction,
            onPress: loading || error != null
                ? null
                : () => _addRelation(context, ref, relations),
            size: AppSpacing.s32,
            iconSize: AppIconSizes.xs,
          ),
        ),
        if (onCreateDecision case final action?) ...[
          FButton(
            variant: FButtonVariant.outline,
            onPress: action,
            prefix: const Icon(
              FLucideIcons.gitBranchPlus,
              size: AppIconSizes.sm,
            ),
            child: Text(l10n.knowledgeCreateDecisionFromNoteAction),
          ),
          const SizedBox(height: AppSpacing.s10),
        ],
        if (error != null)
          Text(
            userSafeErrorMessage(context, error),
            style: context.captionStyle.copyWith(
              color: context.theme.colors.destructive,
            ),
          )
        else if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.s12),
              child: FCircularProgress(),
            ),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
            child: Text(
              l10n.knowledgeRelationsEmpty,
              style: context.captionStyle,
            ),
          )
        else
          AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _KnowledgeRelationRow(
                    item: items[index],
                    onOpen: () => _open(context, items[index]),
                    onRemove: () => _removeRelation(ref, items[index].relation),
                  ),
                  if (index != items.length - 1)
                    const AppGroupedDivider(
                      indent: AppSpacing.s14,
                      endIndent: AppSpacing.s14,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addRelation(
    BuildContext context,
    WidgetRef ref,
    List<KnowledgeRelation> relations,
  ) async {
    final excluded = <String>{
      for (final relation in relations)
        if (relation.fromKind == subjectKind.name &&
            relation.fromId == subjectId)
          '${relation.toKind}:${relation.toId}'
        else
          '${relation.fromKind}:${relation.fromId}',
    };
    final target = await showKnowledgeRelationPickerSheet(
      context: context,
      subjectKind: subjectKind.name,
      subjectId: subjectId,
      excludedTargetKeys: excluded,
    );
    if (target == null) return;
    final repository = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    final relation = KnowledgeRelation(
      id: knowledgeRelationId(
        fromKind: subjectKind.name,
        fromId: subjectId,
        relation: KnowledgeRelationType.relatedTo,
        toKind: target.kind,
        toId: target.id,
      ),
      fromKind: subjectKind.name,
      fromId: subjectId,
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
    await repository.upsertRelation(relation);
  }

  Future<void> _removeRelation(
    WidgetRef ref,
    KnowledgeRelation relation,
  ) async {
    final repository = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    await repository.deleteRelation(
      id: relation.id,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
  }

  void _open(BuildContext context, _RelatedKnowledgeItem item) {
    context.push(
      item.kind == KnowledgeEntryKind.note.name
          ? KnowledgeRoutes.note(item.id)
          : KnowledgeRoutes.decision(item.id),
    );
  }

  List<_RelatedKnowledgeItem> _resolveItems({
    required List<KnowledgeRelation> relations,
    required List<KnowledgeNote> notes,
    required List<KnowledgeDecision> decisions,
  }) {
    final notesById = {for (final note in notes) note.id: note};
    final decisionsById = {
      for (final decision in decisions) decision.id: decision,
    };
    final items = <_RelatedKnowledgeItem>[];
    for (final relation in relations) {
      final subjectIsFrom =
          relation.fromKind == subjectKind.name && relation.fromId == subjectId;
      final kind = subjectIsFrom ? relation.toKind : relation.fromKind;
      final id = subjectIsFrom ? relation.toId : relation.fromId;
      if (kind == KnowledgeEntryKind.note.name) {
        final note = notesById[id];
        if (note == null) continue;
        items.add(
          _RelatedKnowledgeItem(
            relation: relation,
            kind: kind,
            id: id,
            title: note.title,
            excerpt: knowledgeExcerpt(
              note.bodyMd,
              max: kKnowledgeHeadlineExcerptMaxChars,
            ),
            subjectIsFrom: subjectIsFrom,
          ),
        );
      } else if (kind == KnowledgeEntryKind.decision.name) {
        final decision = decisionsById[id];
        if (decision == null) continue;
        items.add(
          _RelatedKnowledgeItem(
            relation: relation,
            kind: kind,
            id: id,
            title: decision.question,
            excerpt: knowledgeExcerpt(
              decision.rationaleMd.isEmpty
                  ? decision.selectedLabel
                  : decision.rationaleMd,
              max: kKnowledgeHeadlineExcerptMaxChars,
            ),
            subjectIsFrom: subjectIsFrom,
          ),
        );
      }
    }
    return items;
  }
}

class _KnowledgeRelationRow extends StatelessWidget {
  const _KnowledgeRelationRow({
    required this.item,
    required this.onOpen,
    required this.onRemove,
  });

  final _RelatedKnowledgeItem item;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = item.title.isEmpty ? l10n.knowledgeUntitled : item.title;
    final relationLabel = switch ((
      item.relation.relation,
      item.subjectIsFrom,
    )) {
      (KnowledgeRelationType.informs, true) =>
        l10n.knowledgeRelationInformedDecision,
      (KnowledgeRelationType.informs, false) =>
        l10n.knowledgeRelationSourceNote,
      (_, _) =>
        item.kind == KnowledgeEntryKind.note.name
            ? l10n.knowledgeRelationRelatedNote
            : l10n.knowledgeRelationRelatedDecision,
    };
    final subtitle = item.excerpt.isEmpty
        ? relationLabel
        : '$relationLabel · ${item.excerpt}';
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        children: [
          Icon(
            item.kind == KnowledgeEntryKind.note.name
                ? FLucideIcons.fileText
                : FLucideIcons.circleCheck,
            size: AppIconSizes.sm,
            color: colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Semantics(
              button: true,
              label: '$title, $subtitle',
              excludeSemantics: true,
              child: AppTappable(
                onPress: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: context.labelStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              subtitle,
                              style: context.captionStyle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Icon(
                        FLucideIcons.chevronRight,
                        size: AppIconSizes.sm,
                        color: colors.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          AppIconButton(
            key: ValueKey('knowledge-relation-remove-${item.relation.id}'),
            icon: FLucideIcons.unlink,
            tooltip: l10n.knowledgeRelationRemoveAction,
            onPress: onRemove,
            size: AppSpacing.s32,
            iconSize: AppIconSizes.xs,
          ),
        ],
      ),
    );
  }
}

class _RelatedKnowledgeItem {
  const _RelatedKnowledgeItem({
    required this.relation,
    required this.kind,
    required this.id,
    required this.title,
    required this.excerpt,
    required this.subjectIsFrom,
  });

  final KnowledgeRelation relation;
  final String kind;
  final String id;
  final String title;
  final String excerpt;
  final bool subjectIsFrom;
}
