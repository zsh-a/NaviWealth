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

class KnowledgeInboxPage extends ConsumerStatefulWidget {
  const KnowledgeInboxPage({super.key});

  @override
  ConsumerState<KnowledgeInboxPage> createState() => _KnowledgeInboxPageState();
}

class _KnowledgeInboxPageState extends ConsumerState<KnowledgeInboxPage>
    with KnowledgeFabScrollHideMixin {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeInboxTitle,
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: onScrollUpdate,
              child: const _InboxBody(),
            ),
          ),
          Positioned(
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
            child: KnowledgeFloatingActionMotion(
              hidden: fabHidden,
              child: KnowledgeFloatingActionSurface(
                child: FButton(
                  variant: FButtonVariant.ghost,
                  prefix: const Icon(
                    FLucideIcons.plus,
                    size: AppIconSizes.sm,
                    color: Color(0xFFFFFFFF),
                  ),
                  onPress: () => showKnowledgeCaptureSheet(context, ref),
                  child: Text(
                    l10n.knowledgeCaptureAction,
                    style: const TextStyle(color: Color(0xFFFFFFFF)),
                  ),
                ),
              ),
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
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const KnowledgeLoadingState();
        final owner = ownerSnap.data!;
        return repoAsync.when(
          loading: () => const KnowledgeLoadingState(),
          error: (e, _) => KnowledgeErrorState(
            title: AppLocalizations.of(context).knowledgeInboxLoadFailedTitle,
            message: '$e',
            onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
          ),
          data: (repo) {
            return StreamBuilder<List<KnowledgeNote>>(
              stream: repo.watchNotes(ownerUserId: owner, limit: 50),
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const <KnowledgeNote>[];
                if (notes.isEmpty) {
                  return KnowledgeEmptyState(
                    icon: FLucideIcons.inbox,
                    title: l10n.knowledgeInboxEmptyTitle,
                    message: l10n.knowledgeInboxEmptyBody,
                  );
                }
                return KnowledgePullToRefresh(
                  onRefresh: () => _refreshKnowledgeRepository(ref),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

Future<void> _refreshKnowledgeRepository(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  await ref.read(knowledgeRepositoryProvider.future);
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final KnowledgeNote note;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final candidateKind = _extractCandidateKind(note.tags);
    return KnowledgeSection.item(
      title: note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
      children: [
        if (note.bodyMd.isNotEmpty)
          Text(
            knowledgeExcerpt(note.bodyMd),
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
        const SizedBox(height: AppSpacing.s6),
        Row(
          children: [
            Icon(
              FLucideIcons.clock,
              size: AppIconSizes.xs,
              color: colors.mutedForeground,
            ),
            const SizedBox(width: AppSpacing.s4),
            Text(
              knowledgeDate(context, note.createdAt),
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
            if (candidateKind != null) ...[
              const SizedBox(width: AppSpacing.s8),
              KnowledgeStatusLabel(label: candidateKind),
            ],
            if (note.projectTag != null &&
                note.projectTag!.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.s8),
              Icon(
                FLucideIcons.folder,
                size: AppIconSizes.xs,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s4),
              Flexible(
                child: Text(
                  note.projectTag!,
                  style: typography.xs.copyWith(
                    color: colors.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Extracts the AI-assigned candidate kind (e.g. "routine_candidate" → "routine")
/// from the note's tags, or null if none.
String? _extractCandidateKind(List<String> tags) {
  const prefix = 'kind:';
  const suffix = '_candidate';
  for (final tag in tags) {
    if (tag.startsWith(prefix) && tag.endsWith(suffix)) {
      return tag.substring(prefix.length, tag.length - suffix.length);
    }
  }
  return null;
}
