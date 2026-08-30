import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';

class KnowledgeRelationTarget {
  const KnowledgeRelationTarget({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
  });

  final String kind;
  final String id;
  final String title;
  final String subtitle;
  final DateTime updatedAt;

  String get key => '$kind:$id';
}

Future<KnowledgeRelationTarget?> showKnowledgeRelationPickerSheet({
  required BuildContext context,
  required String subjectKind,
  required String subjectId,
  required Set<String> excludedTargetKeys,
}) {
  return showAppSheet<KnowledgeRelationTarget>(
    context: context,
    title: AppLocalizations.of(context).knowledgeRelationPickerTitle,
    scrollable: false,
    builder: (_) => _KnowledgeRelationPickerBody(
      subjectKind: subjectKind,
      subjectId: subjectId,
      excludedTargetKeys: excludedTargetKeys,
    ),
  );
}

class _KnowledgeRelationPickerBody extends ConsumerStatefulWidget {
  const _KnowledgeRelationPickerBody({
    required this.subjectKind,
    required this.subjectId,
    required this.excludedTargetKeys,
  });

  final String subjectKind;
  final String subjectId;
  final Set<String> excludedTargetKeys;

  @override
  ConsumerState<_KnowledgeRelationPickerBody> createState() =>
      _KnowledgeRelationPickerBodyState();
}

class _KnowledgeRelationPickerBodyState
    extends ConsumerState<_KnowledgeRelationPickerBody> {
  final _search = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notesAsync = ref.watch(knowledgeNotesProvider);
    final decisionsAsync = ref.watch(knowledgeDecisionsProvider);
    final error = notesAsync.error ?? decisionsAsync.error;
    final loading =
        (notesAsync.isLoading && !notesAsync.hasValue) ||
        (decisionsAsync.isLoading && !decisionsAsync.hasValue);
    final targets = _targets(
      l10n,
      notesAsync.value ?? const <KnowledgeNote>[],
      decisionsAsync.value ?? const <KnowledgeDecision>[],
    );
    return SizedBox(
      height: AppControlHeights.searchSheet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(
              controller: _search,
              onChange: (value) => setState(() => _query = value.text.trim()),
            ),
            autofocus: true,
            hint: l10n.knowledgeRelationPickerSearchHint,
          ),
          const SizedBox(height: AppSpacing.s12),
          Expanded(
            child: error != null
                ? AppEmptyState.error(
                    title: l10n.commonLoadFailed,
                    message: userSafeErrorMessage(context, error),
                    retryLabel: l10n.commonRetry,
                    onRetry: () {
                      ref.invalidate(knowledgeNotesProvider);
                      ref.invalidate(knowledgeDecisionsProvider);
                    },
                    compact: true,
                  )
                : loading
                ? kDefaultLoading
                : targets.isEmpty
                ? AppEmptyState(
                    icon: _query.isEmpty
                        ? FLucideIcons.link2
                        : FLucideIcons.searchX,
                    title: _query.isEmpty
                        ? l10n.knowledgeRelationPickerEmpty
                        : l10n.knowledgeRelationPickerNoResults,
                    compact: true,
                  )
                : AppGroupedSurface(
                    padding: EdgeInsets.zero,
                    child: ListView.separated(
                      itemCount: targets.length,
                      separatorBuilder: (_, _) => const AppGroupedDivider(),
                      itemBuilder: (context, index) {
                        final target = targets[index];
                        return AppNavRow(
                          key: ValueKey(
                            'knowledge-relation-target-${target.key}',
                          ),
                          icon: target.kind == KnowledgeEntryKind.note.name
                              ? FLucideIcons.fileText
                              : FLucideIcons.circleCheck,
                          title: target.title,
                          subtitle: target.subtitle,
                          titleMaxLines: 1,
                          subtitleMaxLines: 2,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s14,
                            vertical: AppSpacing.s10,
                          ),
                          onTap: () => Navigator.of(context).pop(target),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<KnowledgeRelationTarget> _targets(
    AppLocalizations l10n,
    List<KnowledgeNote> notes,
    List<KnowledgeDecision> decisions,
  ) {
    final targets = <KnowledgeRelationTarget>[
      for (final note in notes)
        KnowledgeRelationTarget(
          kind: KnowledgeEntryKind.note.name,
          id: note.id,
          title: note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
          subtitle: knowledgeExcerpt(
            note.bodyMd,
            max: kKnowledgeHeadlineExcerptMaxChars,
          ),
          updatedAt: note.sync.updatedAt,
        ),
      for (final decision in decisions)
        KnowledgeRelationTarget(
          kind: KnowledgeEntryKind.decision.name,
          id: decision.id,
          title: decision.question,
          subtitle: knowledgeExcerpt(
            decision.rationaleMd.isEmpty
                ? decision.selectedLabel
                : decision.rationaleMd,
            max: kKnowledgeHeadlineExcerptMaxChars,
          ),
          updatedAt: decision.sync.updatedAt,
        ),
    ];
    final normalizedQuery = _query.toLowerCase();
    targets.removeWhere(
      (target) =>
          (target.kind == widget.subjectKind &&
              target.id == widget.subjectId) ||
          widget.excludedTargetKeys.contains(target.key) ||
          (normalizedQuery.isNotEmpty &&
              !'${target.title} ${target.subtitle}'.toLowerCase().contains(
                normalizedQuery,
              )),
    );
    targets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return targets.take(50).toList(growable: false);
  }
}
