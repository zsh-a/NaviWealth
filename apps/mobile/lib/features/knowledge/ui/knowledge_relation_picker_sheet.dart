import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_repository.dart';
import '../data/knowledge_search_service.dart';
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
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final searchProvider = knowledgeLibrarySearchProvider((
      query: _query,
      kind: null,
      tag: null,
    ));
    final notesAsync = ref.watch(
      knowledgeLibraryNotesProvider((limit: 50, tag: null)),
    );
    final decisionsAsync = ref.watch(knowledgeLibraryDecisionsProvider(50));
    final searchAsync = _query.isEmpty ? null : ref.watch(searchProvider);
    final error = searchAsync == null
        ? notesAsync.error ?? decisionsAsync.error
        : searchAsync.error;
    final loading = searchAsync == null
        ? (notesAsync.isLoading && !notesAsync.hasValue) ||
              (decisionsAsync.isLoading && !decisionsAsync.hasValue)
        : searchAsync.isLoading && !searchAsync.hasValue;
    final targets = searchAsync == null
        ? _targets(
            l10n,
            notesAsync.value ?? const <KnowledgeNote>[],
            decisionsAsync.value ?? const <KnowledgeDecision>[],
          )
        : [
            for (final hit in searchAsync.value ?? const <KnowledgeSearchHit>[])
              KnowledgeRelationTarget(
                kind: hit.kind,
                id: hit.id,
                title: hit.title.isEmpty ? l10n.knowledgeUntitled : hit.title,
                subtitle: knowledgeSearchExcerpt(
                  hit.document.searchText,
                  _query,
                ),
                updatedAt: hit.document.updatedAt,
              ),
          ];
    targets.removeWhere(
      (target) =>
          (target.kind == widget.subjectKind &&
              target.id == widget.subjectId) ||
          widget.excludedTargetKeys.contains(target.key),
    );
    return SizedBox(
      height: AppControlHeights.searchSheet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(
              controller: _search,
              onChange: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() => _query = value.text.trim());
                });
              },
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
                      ref.invalidate(
                        knowledgeLibraryNotesProvider((limit: 50, tag: null)),
                      );
                      ref.invalidate(knowledgeLibraryDecisionsProvider(50));
                      ref.invalidate(searchProvider);
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
    return targets.take(50).toList();
  }
}
