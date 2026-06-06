/// KnowledgeOS Inbox tab (`docs/knowledgeos-domain.md` §5).
///
/// Renders captured Notes. The FAB opens [showKnowledgeCaptureSheet] —
/// a unified AI-native capture (single textarea + post-save inline
/// upgrade suggestion). The old typed `_NewNoteSheet` is gone; promoting
/// a capture to Decision / Routine / etc. happens through the inline
/// upgrade card in the sheet itself, not by picking the type up front.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ask_ai.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';
import 'knowledge_capture_sheet.dart';

class KnowledgeInboxPage extends ConsumerWidget {
  const KnowledgeInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeInboxTitle,
      child: Stack(
        children: [
          const Positioned.fill(child: _InboxBody()),
          Positioned(
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
            child: FButton(
              prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
              onPress: () => showKnowledgeCaptureSheet(context, ref),
              child: Text(l10n.knowledgeCaptureAction),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxBody extends ConsumerWidget {
  const _InboxBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Inbox is the KnowledgeOS "AI 助理" front door: the bar stays
    // pinned above the note list (visible even while loading / empty) so
    // add / query / dedupe / suggest are always one tap away.
    return const Column(
      children: [
        _AiAssistantBar(),
        Expanded(child: _NotesList()),
      ],
    );
  }
}

/// The agent entry: a tappable ask/capture pill + three quick-action
/// chips. Each routes through `askAi` conversation mode, which (on the
/// knowledge route) opens the device agent loop scoped to KnowledgeOS
/// tools + prompt with the composer seeded. The user sends; the agent
/// then chains the right tools:
///
///  - pill     → empty composer (type a capture or a question freeform)
///  - 查重     → seeds dedupe (agent → find_similar_knowledge → propose_merge)
///  - 本周建议 → seeds suggest (agent → review_knowledge_health → propose_*)
///  - 搜知识   → seeds cross-type search (agent → search_knowledge)
///
/// Conversation prefill (not auto-fired invocation intents) keeps this
/// off the regression-corpus / renderer fixture path while still
/// delivering the full agentic loop on send.
class _AiAssistantBar extends ConsumerWidget {
  const _AiAssistantBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: DomainAiPromptBar(
        hint: l10n.knowledgeAiPromptHint,
        onPress: () => askAi(context, ref, prefill: ''),
        actions: [
          DomainAiPromptAction(
            label: l10n.knowledgeAiDedupeAction,
            icon: FLucideIcons.gitMerge,
            onPress: () =>
                askAi(context, ref, prefill: l10n.knowledgeAiDedupePrompt),
          ),
          DomainAiPromptAction(
            label: l10n.knowledgeAiWeeklyAction,
            icon: FLucideIcons.lightbulb,
            onPress: () =>
                askAi(context, ref, prefill: l10n.knowledgeAiWeeklyPrompt),
          ),
          DomainAiPromptAction(
            label: l10n.knowledgeAiSearchAction,
            icon: FLucideIcons.search,
            onPress: () =>
                askAi(context, ref, prefill: l10n.knowledgeAiSearchPrompt),
          ),
        ],
      ),
    );
  }
}

class _NotesList extends ConsumerWidget {
  const _NotesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(knowledgeRepositoryProvider);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const _Centered(child: FProgress());
        final owner = ownerSnap.data!;
        return repoAsync.when(
          loading: () => const _Centered(child: FProgress()),
          error: (e, _) => _ErrorState(
            message: '$e',
            onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
          ),
          data: (repo) {
            return StreamBuilder<List<KnowledgeNote>>(
              stream: repo.watchNotes(ownerUserId: owner, limit: 50),
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const <KnowledgeNote>[];
                if (notes.isEmpty) return const _EmptyState();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s16,
                    AppSpacing.s8,
                    AppSpacing
                        .s16, // Bottom padding leaves room for the floating FAB.
                    AppSpacing.s64,
                  ),
                  itemCount: notes.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s8),
                  itemBuilder: (context, i) => _NoteCard(note: notes[i]),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final KnowledgeNote note;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
            style: typography.md.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (note.bodyMd.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              knowledgeExcerpt(note.bodyMd),
              style: typography.sm.copyWith(color: colors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.inbox,
      title: l10n.knowledgeInboxEmptyTitle,
      message: l10n.knowledgeInboxEmptyBody,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState.error(
      title: l10n.knowledgeInboxLoadFailedTitle,
      message: message,
      action: FButton(
        variant: FButtonVariant.ghost,
        onPress: onRetry,
        child: Text(l10n.commonRetry),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}
