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
    // Headerless cockpit root, same as the other domains' Today briefs: the
    // editorial greeting ([KnowledgeGreetingHeader]) replaces the static
    // page title and hosts the injected shell chrome via [ShellActionRow]
    // plus the capture action that used to live in the tab header. Global
    // chrome (sync strip, undo banner) is injected by DomainTabsShell.
    return ShellCanvasScaffold(
      childPad: false,
      child: ShellTabPause(
        routePath: KnowledgeRoutes.inbox,
        child: _InboxContent(
          recentNotes: ref.watch(knowledgeRecentNotesProvider),
          dueReviews: ref.watch(knowledgeDueReviewsProvider),
        ),
      ),
    );
  }
}

class _InboxContent extends ConsumerWidget {
  const _InboxContent({required this.recentNotes, required this.dueReviews});

  final AsyncValue<List<KnowledgeNote>> recentNotes;
  final AsyncValue<List<KnowledgeDecision>> dueReviews;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(knowledgeNotesProvider);
    ref.invalidate(knowledgeDecisionsProvider);
    await ref.read(knowledgeNotesProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Scope above the loading/data branches: the entrance watermark survives
    // pull-to-refresh, so recycled rows never replay the entrance when they
    // scroll back into view.
    return AppEntranceScope(child: _buildBody(context, ref, l10n));
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    if (recentNotes.isLoading || dueReviews.isLoading) {
      return AppListPageSkeleton(
        padding: shellTabContentPadding(context),
        showControls: false,
      );
    }
    if (recentNotes.hasError || dueReviews.hasError) {
      return AppEmptyState.error(
        title: l10n.commonLoadFailed,
        retryLabel: l10n.commonRetry,
        onRetry: () {
          ref.invalidate(knowledgeNotesProvider);
          ref.invalidate(knowledgeDecisionsProvider);
        },
        compact: true,
      );
    }

    final notes = recentNotes.asData?.value ?? const <KnowledgeNote>[];
    final decisions = dueReviews.asData?.value ?? const <KnowledgeDecision>[];
    final now = DateTime.now().toUtc();
    final hasOverdue = decisions.any(
      (decision) => (decision.daysOverdue(now) ?? 0) > 0,
    );

    return BriefLazyListScaffold(
      padding: shellTabContentPadding(context),
      onRefresh: () => _refresh(ref),
      greeting: const KnowledgeGreetingHeader(),
      // The due-review section is the inbox's reason to exist, so it takes
      // the stage slot directly under the greeting.
      stage: decisions.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader.module(
                  title: l10n.knowledgeInboxDueReviewsTitle,
                  titleColor: hasOverdue
                      ? context.appTheme.status.warning.fg
                      : null,
                  trailing: AppBadge(
                    label: '${decisions.length}',
                    size: AppBadgeSize.compact,
                    tone: hasOverdue ? AppBadgeTone.warning : AppBadgeTone.info,
                  ),
                ),
                for (var index = 0; index < decisions.length; index++) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.s10),
                  AppOnceEntrance(
                    index: index,
                    child: _DueDecisionTile(decision: decisions[index]),
                  ),
                ],
              ],
            ),
      modules: [
        if (decisions.isEmpty && notes.isEmpty)
          AppEmptyState(
            icon: FLucideIcons.notebookPen,
            title: l10n.knowledgeInboxEmptyTitle,
            message: l10n.knowledgeInboxEmptyBody,
            action: AppActionButton(
              onPress: () => showKnowledgeCaptureSheet(context),
              child: Text(l10n.knowledgeCaptureAction),
            ),
          ),
      ],
      listHeader: notes.isEmpty
          ? null
          : SectionHeader.module(
              title: l10n.knowledgeInboxRecentNotesTitle,
              trailing: AppBadge(
                label: '${notes.length}',
                size: AppBadgeSize.compact,
              ),
            ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return AppOnceEntrance(
          // Offset past the due-review rows: both lists share one tracker.
          index: decisions.length + index,
          child: KnowledgeEntryTile(
            key: ValueKey<String>('knowledge-inbox-note-${note.id}'),
            title: note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
            subtitle: knowledgeExcerpt(note.bodyMd),
            tags: note.tags,
            kindLabel: l10n.knowledgeKindNote,
            icon: FLucideIcons.fileText,
            onPress: () => context.push(KnowledgeRoutes.note(note.id)),
          ),
        );
      },
    );
  }
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
