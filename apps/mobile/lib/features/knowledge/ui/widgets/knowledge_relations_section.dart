import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/forms/form_dirty_guard.dart';
import '../../../../core/forms/form_submission.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../application/knowledge_relation_service.dart';
import '../../composition/knowledge_route_paths.dart';
import '../../data/knowledge_repository.dart';
import '../../data/knowledge_search_service.dart';
import '../../data/providers.dart';
import '../../domain/knowledge_models.dart';
import '../../domain/knowledge_text.dart';
import '../knowledge_relation_picker_sheet.dart';
import '../knowledge_relation_suggestions_sheet.dart';
import 'knowledge_edit_notice.dart';

class KnowledgeRelationsSection extends ConsumerStatefulWidget {
  const KnowledgeRelationsSection({
    super.key,
    required this.subjectKind,
    required this.subjectId,
    this.subjectText,
    this.onCreateDecision,
  });

  final KnowledgeEntryKind subjectKind;
  final String subjectId;
  final String? subjectText;
  final VoidCallback? onCreateDecision;

  @override
  ConsumerState<KnowledgeRelationsSection> createState() =>
      _KnowledgeRelationsSectionState();
}

class _KnowledgeRelationsSectionState
    extends ConsumerState<KnowledgeRelationsSection>
    with
        FormDirtyGuard<KnowledgeRelationsSection>,
        FormSubmission<KnowledgeRelationsSection> {
  KnowledgeEntryKind get subjectKind => widget.subjectKind;
  String get subjectId => widget.subjectId;
  String? get subjectText => widget.subjectText;
  VoidCallback? get onCreateDecision => widget.onCreateDecision;
  bool _saving = false;
  bool _pickerOpen = false;

  @override
  String get leaveFallback => KnowledgeRoutes.library;

  KnowledgeRelationSubject get _subject =>
      (kind: subjectKind.name, id: subjectId);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final relationsAsync = ref.watch(
      knowledgeRelationsForObjectProvider(_subject),
    );
    final notesAsync = ref.watch(knowledgeRelationNotesProvider(_subject));
    final decisionsAsync = ref.watch(
      knowledgeRelationDecisionsProvider(_subject),
    );
    final error =
        relationsAsync.error ?? notesAsync.error ?? decisionsAsync.error;
    final loading =
        (relationsAsync.isLoading && !relationsAsync.hasValue) ||
        (notesAsync.isLoading && !notesAsync.hasValue) ||
        (decisionsAsync.isLoading && !decisionsAsync.hasValue);
    final relations = relationsAsync.value ?? const <KnowledgeRelation>[];
    final notes = notesAsync.value ?? const <KnowledgeNote>[];
    final decisions = decisionsAsync.value ?? const <KnowledgeDecision>[];
    final items = _resolveItems(
      relations: relations,
      notes: notes,
      decisions: decisions,
    );
    final suggestionText =
        subjectText ?? _subjectText(notes: notes, decisions: decisions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.module(
          title: l10n.knowledgeRelationsTitle,
          subtitle: l10n.knowledgeRelationsSubtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                key: const Key('knowledge-relations-discover'),
                icon: FLucideIcons.sparkles,
                tooltip: l10n.knowledgeRelationDiscoverAction,
                onPress:
                    _saving ||
                        _pickerOpen ||
                        loading ||
                        error != null ||
                        suggestionText.trim().isEmpty
                    ? null
                    : () => _discoverRelations(
                        context,
                        relations,
                        suggestionText,
                      ),
                size: AppSpacing.s32,
                iconSize: AppIconSizes.xs,
              ),
              const SizedBox(width: AppSpacing.s4),
              AppIconButton(
                key: const Key('knowledge-relations-add'),
                icon: FLucideIcons.link2,
                tooltip: l10n.knowledgeRelationAddAction,
                onPress: _saving || _pickerOpen || loading || error != null
                    ? null
                    : () => _addRelation(context, ref, relations),
                size: AppSpacing.s32,
                iconSize: AppIconSizes.xs,
              ),
            ],
          ),
        ),
        if (onCreateDecision case final action?) ...[
          FButton(
            variant: FButtonVariant.outline,
            onPress: _saving ? null : action,
            prefix: const Icon(
              FLucideIcons.gitBranchPlus,
              size: AppIconSizes.sm,
            ),
            child: Text(l10n.knowledgeCreateDecisionFromNoteAction),
          ),
          const SizedBox(height: AppSpacing.s10),
        ],
        if (error != null)
          AppEmptyState.error(
            title: l10n.commonLoadFailed,
            message: userSafeErrorMessage(context, error),
            retryLabel: l10n.commonRetry,
            onRetry: () {
              ref.invalidate(knowledgeRelationsForObjectProvider(_subject));
              ref.invalidate(knowledgeRelationNotesProvider(_subject));
              ref.invalidate(knowledgeRelationDecisionsProvider(_subject));
            },
            compact: true,
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
                    onRemove: _saving
                        ? null
                        : () => _removeRelation(ref, items[index].relation),
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
        if (submissionFailureMessage case final message?) ...[
          const SizedBox(height: AppSpacing.s8),
          AppStatusBanner(message: message, kind: AppStatusKind.error),
        ],
      ],
    );
  }

  Future<void> _addRelation(
    BuildContext context,
    WidgetRef ref,
    List<KnowledgeRelation> relations,
  ) async {
    if (_pickerOpen || _saving) return;
    setState(() => _pickerOpen = true);
    try {
      await showKnowledgeRelationPickerSheet(
        context: context,
        subjectKind: subjectKind.name,
        subjectId: subjectId,
        excludedTargetKeys: _excludedTargetKeys(relations),
        onSelect: (target) async {
          dirty.busy = true;
          try {
            final service = await ref.read(
              knowledgeRelationServiceProvider.future,
            );
            await service.add(
              fromKind: subjectKind.name,
              fromId: subjectId,
              toKind: target.kind,
              toId: target.id,
            );
          } finally {
            dirty.busy = false;
          }
        },
      );
    } finally {
      if (mounted) setState(() => _pickerOpen = false);
    }
  }

  Future<void> _discoverRelations(
    BuildContext context,
    List<KnowledgeRelation> relations,
    String subjectText,
  ) async {
    if (_pickerOpen || _saving) return;
    setState(() => _pickerOpen = true);
    try {
      await showKnowledgeRelationSuggestionsSheet(
        context: context,
        subjectKind: subjectKind.name,
        subjectId: subjectId,
        subjectText: subjectText,
        excludedTargetKeys: _excludedTargetKeys(relations),
        onBusyChanged: (busy) {
          if (mounted) dirty.busy = busy;
        },
      );
    } finally {
      if (mounted) setState(() => _pickerOpen = false);
    }
  }

  Set<String> _excludedTargetKeys(List<KnowledgeRelation> relations) => {
    for (final relation in relations)
      if (relation.fromKind == subjectKind.name && relation.fromId == subjectId)
        '${relation.toKind}:${relation.toId}'
      else
        '${relation.fromKind}:${relation.fromId}',
  };

  String _subjectText({
    required List<KnowledgeNote> notes,
    required List<KnowledgeDecision> decisions,
  }) {
    if (subjectKind == KnowledgeEntryKind.note) {
      for (final note in notes) {
        if (note.id == subjectId) {
          return KnowledgeSearchDocument.fromNote(note).searchText;
        }
      }
      return '';
    }
    for (final decision in decisions) {
      if (decision.id == subjectId) {
        return KnowledgeSearchDocument.fromDecision(decision).searchText;
      }
    }
    return '';
  }

  Future<void> _removeRelation(
    WidgetRef ref,
    KnowledgeRelation relation,
  ) async {
    if (_saving) return;
    late KnowledgeRelationService service;
    final l10n = AppLocalizations.of(context);
    await submitForm<KnowledgeRelation>(
      dirty: dirty,
      onBusyChanged: (busy) => setState(() => _saving = busy),
      commit: () async {
        service = await ref.read(knowledgeRelationServiceProvider.future);
        return service.remove(relation);
      },
      leave: () {},
      failureMessage: (error) => knowledgeEditFailureMessage(context, error),
      successMessage: l10n.commonDeleted,
      undo: FormUndoPresentation<KnowledgeRelation>(
        buildAction: (receipt) =>
            FormUndoAction(() => service.restore(receipt)),
        actionLabel: l10n.commonUndo,
        successMessage: l10n.commonUndoSucceeded,
        failureMessage: (error) => knowledgeEditFailureMessage(context, error),
        retryLabel: l10n.commonRetry,
      ),
      tag: 'knowledge-relation-remove',
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
  final VoidCallback? onRemove;

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
