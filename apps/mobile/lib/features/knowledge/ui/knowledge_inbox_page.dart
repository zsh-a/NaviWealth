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
import 'knowledge_capture_sheet.dart';
import 'widgets/knowledge_entry_tile.dart';

class KnowledgeInboxPage extends ConsumerWidget {
  const KnowledgeInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeInboxTitle,
      directActionBudget: 1,
      actions: <ShellHeaderActionSpec>[
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.knowledgeCaptureAction,
          onPress: () => showKnowledgeCaptureSheet(context),
        ),
      ],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (recentNotes.isLoading || dueReviews.isLoading) {
      return kDefaultLoading;
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
    if (notes.isEmpty && decisions.isEmpty) {
      return AppEmptyState(
        icon: FLucideIcons.notebookPen,
        title: l10n.knowledgeInboxEmptyTitle,
        message: l10n.knowledgeInboxEmptyBody,
        action: AppActionButton(
          onPress: () => showKnowledgeCaptureSheet(context),
          child: Text(l10n.knowledgeCaptureAction),
        ),
      );
    }

    return ListView(
      padding: shellTabContentPadding(context),
      children: [
        if (decisions.isNotEmpty) ...[
          _SectionHeader(
            title: l10n.knowledgeInboxDueReviewsTitle,
            count: decisions.length,
          ),
          const SizedBox(height: AppSpacing.s10),
          for (var index = 0; index < decisions.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.s10),
            _DueDecisionTile(decision: decisions[index]),
          ],
        ],
        if (decisions.isNotEmpty && notes.isNotEmpty)
          const SizedBox(height: AppSpacing.s24),
        if (notes.isNotEmpty) ...[
          _SectionHeader(
            title: l10n.knowledgeInboxRecentNotesTitle,
            count: notes.length,
          ),
          const SizedBox(height: AppSpacing.s10),
          for (var index = 0; index < notes.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.s10),
            KnowledgeEntryTile(
              key: ValueKey<String>('knowledge-inbox-note-${notes[index].id}'),
              title: notes[index].title.isEmpty
                  ? l10n.knowledgeUntitled
                  : notes[index].title,
              subtitle: notes[index].bodyMd,
              tags: notes[index].tags,
              kindLabel: l10n.knowledgeKindNote,
              icon: FLucideIcons.fileText,
              onPress: () =>
                  context.push(KnowledgeRoutes.note(notes[index].id)),
            ),
          ],
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: context.rowTitleStyle)),
        FBadge(child: Text('$count')),
      ],
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
