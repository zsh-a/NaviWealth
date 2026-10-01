import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/form_dirty_guard.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_relation_service.dart';
import '../data/knowledge_repository.dart';
import '../data/knowledge_search_service.dart';
import '../data/providers.dart';
import 'widgets/knowledge_edit_notice.dart';

Future<void> showKnowledgeRelationSuggestionsSheet({
  required BuildContext context,
  required String subjectKind,
  required String subjectId,
  required String subjectText,
  required Set<String> excludedTargetKeys,
  ValueChanged<bool>? onBusyChanged,
}) {
  return showGuardedFormSheet<void>(
    context: context,
    builder: (_, dirty) => _KnowledgeRelationSuggestionsBody(
      subjectKind: subjectKind,
      subjectId: subjectId,
      subjectText: subjectText,
      excludedTargetKeys: excludedTargetKeys,
      dirty: dirty,
      onBusyChanged: onBusyChanged,
    ),
  );
}

class _KnowledgeRelationSuggestionsBody extends ConsumerStatefulWidget {
  const _KnowledgeRelationSuggestionsBody({
    required this.subjectKind,
    required this.subjectId,
    required this.subjectText,
    required this.excludedTargetKeys,
    required this.dirty,
    this.onBusyChanged,
  });

  final String subjectKind;
  final String subjectId;
  final String subjectText;
  final Set<String> excludedTargetKeys;
  final FormDirtyController dirty;
  final ValueChanged<bool>? onBusyChanged;

  @override
  ConsumerState<_KnowledgeRelationSuggestionsBody> createState() =>
      _KnowledgeRelationSuggestionsBodyState();
}

class _KnowledgeRelationSuggestionsBodyState
    extends ConsumerState<_KnowledgeRelationSuggestionsBody> {
  late final Set<String> _linkedKeys = <String>{...widget.excludedTargetKeys};
  final Set<String> _savingKeys = <String>{};
  String? _failureMessage;

  KnowledgeRelationSuggestionsRequest get _request =>
      (subjectId: widget.subjectId, text: widget.subjectText);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(knowledgeRelationSuggestionsProvider(_request));
    return AppSheet(
      title: l10n.knowledgeRelationSuggestionsTitle,
      scrollable: false,
      child: SizedBox(
        height: AppControlHeights.searchSheet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppStatusBanner(
              compact: true,
              kind: AppStatusKind.info,
              message: l10n.knowledgeRelationSuggestionsDisclosure,
            ),
            const SizedBox(height: AppSpacing.s12),
            if (_failureMessage case final message?) ...[
              AppStatusBanner(message: message, kind: AppStatusKind.error),
              const SizedBox(height: AppSpacing.s8),
            ],
            Expanded(
              child: value.when(
                loading: () => kDefaultLoading,
                error: (error, _) => AppEmptyState.error(
                  title: l10n.knowledgeRelationSuggestionsUnavailable,
                  message: userSafeErrorMessage(context, error),
                  retryLabel: l10n.commonRetry,
                  onRetry: () => ref.invalidate(
                    knowledgeRelationSuggestionsProvider(_request),
                  ),
                  compact: true,
                ),
                data: (hits) {
                  final suggestions = _visibleSuggestions(hits);
                  if (suggestions.isEmpty) {
                    return AppEmptyState(
                      icon: hits.isEmpty
                          ? FLucideIcons.sparkles
                          : FLucideIcons.badgeCheck,
                      title: hits.isEmpty
                          ? l10n.knowledgeRelationSuggestionsEmpty
                          : l10n.knowledgeRelationSuggestionsComplete,
                      message: hits.isEmpty
                          ? l10n.knowledgeRelationSuggestionsEmptyBody
                          : null,
                      compact: true,
                    );
                  }
                  return AppGroupedSurface(
                    padding: EdgeInsets.zero,
                    child: ListView.separated(
                      itemCount: suggestions.length,
                      separatorBuilder: (_, _) => const AppGroupedDivider(),
                      itemBuilder: (context, index) {
                        final hit = suggestions[index];
                        return _SuggestionRow(
                          hit: hit,
                          saving: _savingKeys.contains(_key(hit)),
                          onLink: () => _link(hit),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<KnowledgeSimilarityHit> _visibleSuggestions(
    List<KnowledgeSimilarityHit> hits,
  ) {
    final seen = <String>{};
    return hits
        .where((hit) {
          final key = _key(hit);
          return seen.add(key) &&
              !_linkedKeys.contains(key) &&
              !(hit.kind == widget.subjectKind && hit.id == widget.subjectId);
        })
        .toList(growable: false);
  }

  Future<void> _link(KnowledgeSimilarityHit hit) async {
    final key = _key(hit);
    if (_savingKeys.contains(key)) return;
    setState(() {
      _savingKeys.add(key);
      _failureMessage = null;
    });
    widget.dirty.busy = true;
    widget.onBusyChanged?.call(true);
    try {
      final service = await ref.read(knowledgeRelationServiceProvider.future);
      await service.add(
        fromKind: widget.subjectKind,
        fromId: widget.subjectId,
        toKind: hit.kind,
        toId: hit.id,
      );
      if (!mounted) return;
      setState(() => _linkedKeys.add(key));
      ref.invalidate(
        knowledgeRelationsForObjectProvider((
          kind: widget.subjectKind,
          id: widget.subjectId,
        )),
      );
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).knowledgeRelationSuggestionLinked,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = knowledgeEditFailureMessage(context, error);
      setState(() => _failureMessage = message);
      AppMessenger.show(context, ToastKind.error, message);
    } finally {
      if (mounted) {
        setState(() => _savingKeys.remove(key));
        widget.dirty.busy = _savingKeys.isNotEmpty;
      } else {
        _savingKeys.remove(key);
      }
      widget.onBusyChanged?.call(_savingKeys.isNotEmpty);
    }
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.hit,
    required this.saving,
    required this.onLink,
  });

  final KnowledgeSimilarityHit hit;
  final bool saving;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final note = hit.document.note;
    final title = note != null && note.title.isEmpty
        ? l10n.knowledgeUntitled
        : hit.title;
    final kind = hit.kind == KnowledgeEntryKind.note.name
        ? l10n.knowledgeKindNote
        : l10n.knowledgeKindDecision;
    final match = l10n.knowledgeRelationSuggestionMatch(
      (hit.similarity * 100).round(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hit.kind == KnowledgeEntryKind.note.name
                ? FLucideIcons.fileText
                : FLucideIcons.circleCheck,
            size: AppIconSizes.sm,
            color: context.theme.colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s10),
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
                if (hit.document.excerpt.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    hit.document.excerpt,
                    style: context.captionStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: AppSpacing.s4),
                Text('$kind · $match', style: context.microCaptionStyle),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          FButton(
            key: ValueKey<String>(
              'knowledge-relation-suggestion-link-${_key(hit)}',
            ),
            variant: FButtonVariant.outline,
            onPress: saving ? null : onLink,
            child: Text(
              saving
                  ? l10n.commonSaving
                  : l10n.knowledgeRelationSuggestionLinkAction,
            ),
          ),
        ],
      ),
    );
  }
}

String _key(KnowledgeSimilarityHit hit) => '${hit.kind}:${hit.id}';
