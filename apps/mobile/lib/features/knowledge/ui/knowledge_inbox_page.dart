import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'knowledge_capture_sheet.dart';
import 'knowledge_greeting_header.dart';
import 'widgets/knowledge_entry_tile.dart';

class KnowledgeInboxPage extends ConsumerWidget {
  const KnowledgeInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ShellCanvasScaffold(
      childPad: false,
      child: ShellTabPause(
        routePath: KnowledgeRoutes.inbox,
        child: _InboxContent(),
      ),
    );
  }
}

class _InboxContent extends ConsumerStatefulWidget {
  const _InboxContent();

  @override
  ConsumerState<_InboxContent> createState() => _InboxContentState();
}

class _InboxContentState extends ConsumerState<_InboxContent> {
  static const _reviewPreviewLimit = 3;
  bool _allReviews = false;

  Future<void> _refresh() async {
    ref.invalidate(knowledgeNotesProvider);
    ref.invalidate(knowledgeDueReviewsProvider);
    try {
      await Future.wait([
        ref.read(knowledgeNotesProvider.future),
        ref.read(knowledgeDueReviewsProvider.future),
      ]);
    } catch (_) {
      // Each section renders its own retry state while retaining other data.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recentNotes = ref.watch(knowledgeRecentNotesProvider);
    final dueReviews = ref.watch(knowledgeDueReviewsProvider);
    final notes = recentNotes.value ?? const <KnowledgeNote>[];
    final decisions = dueReviews.value ?? const <KnowledgeDecision>[];
    final shownReviews = _allReviews
        ? decisions
        : decisions.take(_reviewPreviewLimit).toList(growable: false);
    final hasOverdue = decisions.any(
      (decision) => (decision.daysOverdue(DateTime.now().toUtc()) ?? 0) > 0,
    );
    final reviewRows = <WidgetBuilder>[
      if (decisions.isNotEmpty || dueReviews.isLoading || dueReviews.hasError)
        (_) => SectionHeader.module(
          title: l10n.knowledgeInboxDueReviewsTitle,
          titleColor: hasOverdue ? context.appTheme.status.warning.fg : null,
          trailing: decisions.isEmpty
              ? null
              : AppBadge(
                  label: '${decisions.length}',
                  size: AppBadgeSize.compact,
                  tone: hasOverdue ? AppBadgeTone.warning : AppBadgeTone.info,
                ),
        ),
      if (dueReviews.hasError)
        (_) => _sectionError(
          l10n,
          () => ref.invalidate(knowledgeDueReviewsProvider),
        )
      else if (dueReviews.isLoading && !dueReviews.hasValue)
        (_) => const SkeletonBox(height: 64),
      for (final decision in shownReviews)
        (_) => _DueDecisionTile(decision: decision),
      if (decisions.length > _reviewPreviewLimit)
        (_) => AppRevealControl(
          expanded: _allReviews,
          collapsedLabel: l10n.knowledgeInboxShowReviews(decisions.length),
          expandedLabel: l10n.knowledgeInboxHideReviews,
          onToggle: () => setState(() => _allReviews = !_allReviews),
        ),
    ];
    final noteRows = <WidgetBuilder>[
      if (notes.isNotEmpty || recentNotes.isLoading || recentNotes.hasError)
        (_) => SectionHeader.module(title: l10n.knowledgeInboxRecentNotesTitle),
      if (recentNotes.hasError)
        (_) => _sectionError(l10n, () => ref.invalidate(knowledgeNotesProvider))
      else if (recentNotes.isLoading && !recentNotes.hasValue)
        (_) => const SkeletonBox(height: 64),
      for (final note in notes)
        (_) => KnowledgeEntryTile(
          key: ValueKey<String>('knowledge-inbox-note-${note.id}'),
          title: note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
          subtitle: knowledgeExcerpt(note.bodyMd),
          tags: note.tags,
          kindLabel: l10n.knowledgeKindNote,
          icon: FLucideIcons.fileText,
          onPress: () => context.push(KnowledgeRoutes.note(note.id)),
        ),
      if (decisions.isEmpty &&
          notes.isEmpty &&
          !recentNotes.isLoading &&
          !dueReviews.isLoading &&
          !recentNotes.hasError &&
          !dueReviews.hasError)
        (_) => AppEmptyState(
          icon: FLucideIcons.notebookPen,
          compact: true,
          title: l10n.knowledgeInboxEmptyTitle,
          message: l10n.knowledgeInboxEmptyBody,
          action: AppActionButton(
            onPress: () => showKnowledgeCaptureSheet(context),
            child: Text(l10n.knowledgeCaptureAction),
          ),
        ),
    ];
    final rows = [...reviewRows, ...noteRows];
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = shellTabContentPadding(context)
            .resolve(Directionality.of(context));
        final contentWidth = constraints.maxWidth - padding.horizontal;
        final split =
            contentWidth >= Breakpoints.contentTwoColumn &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3 &&
            noteRows.isNotEmpty &&
            reviewRows.isNotEmpty;
        if (!split) {
          return BriefLazyListScaffold(
            padding: padding,
            onRefresh: _refresh,
            greeting: const KnowledgeGreetingHeader(),
            itemCount: rows.length,
            itemBuilder: (context, index) => rows[index](context),
          );
        }
        return AppAtmosphere(
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KnowledgeGreetingHeader(),
                const SizedBox(height: AppPageRhythm.module),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, paneConstraints) =>
                        AdaptiveSupportingPane(
                          primary: SizedBox(
                            height: paneConstraints.maxHeight,
                            child: _pane('notes', noteRows),
                          ),
                          supporting: SizedBox(
                            height: paneConstraints.maxHeight,
                            child: _pane('reviews', reviewRows),
                          ),
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pane(String name, List<WidgetBuilder> rows) => AppRefreshIndicator(
    onRefresh: _refresh,
    child: ListView.separated(
      key: PageStorageKey('knowledge-inbox-$name'),
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppPageRhythm.module),
      itemBuilder: (context, index) => rows[index](context),
    ),
  );

  Widget _sectionError(AppLocalizations l10n, VoidCallback onRetry) =>
      AppEmptyState.error(
        title: l10n.commonLoadFailed,
        retryLabel: l10n.commonRetry,
        onRetry: onRetry,
        compact: true,
      );
}

class _DueDecisionTile extends StatelessWidget {
  const _DueDecisionTile({required this.decision});

  final KnowledgeDecision decision;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reviewDate = decision.reviewDate!;
    final days = decision.daysOverdue(DateTime.now().toUtc()) ?? 0;
    final dueLabel = days <= 0
        ? l10n.knowledgeReviewDueToday
        : l10n.knowledgeReviewOverdueDays(days);
    final formattedDate = MaterialLocalizations.of(context)
        .formatMediumDate(reviewDate.toLocal());
    return KnowledgeEntryTile(
      key: ValueKey<String>('knowledge-inbox-review-${decision.id}'),
      title: decision.question,
      subtitle: decision.selectedLabel,
      meta: '$dueLabel · $formattedDate',
      kindLabel: l10n.knowledgeKindDecision,
      icon: FLucideIcons.history,
      accented: true,
      onPress: () => context.push(KnowledgeRoutes.decision(decision.id)),
    );
  }
}
