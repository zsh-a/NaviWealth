/// KnowledgeOS Inbox tab (`docs/domains/knowledgeos-domain.md` §5).
///
/// Renders captured Notes and keeps free-form capture one tap away. Structured
/// classification remains asynchronous Review work so Inbox never waits for
/// an LLM or exposes the KnowledgeOS taxonomy during capture.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/knowledge_llm_client.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_widgets.dart';
import 'knowledge_capture_sheet.dart';
import 'knowledge_item_actions.dart';

final _knowledgeInboxPendingSuggestionsProvider =
    FutureProvider.autoDispose<int>((ref) async {
      ref.watch(aiSuggestionsRefreshProvider);
      final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final triage = await ref.watch(inboxTriageRepositoryProvider.future);
      final pending = await triage.listPending(ownerUserId: owner);
      return pending.fold<int>(0, (sum, record) => sum + record.pending.length);
    });

class KnowledgeInboxPage extends ConsumerWidget {
  const KnowledgeInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pendingSuggestions = ref.watch(
      _knowledgeInboxPendingSuggestionsProvider,
    );
    return ShellTabScaffold(
      title: l10n.knowledgeInboxTitle,
      directActionBudget: 2,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.knowledgeCaptureAction,
          onPress: () => showKnowledgeCaptureSheet(context),
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.clipboardCheck,
          label: l10n.knowledgeTabReview,
          badgeCount: pendingSuggestions.value ?? 0,
          onPress: () => context.push(KnowledgeRoutes.review),
        ),
      ],
      child: const ShellTabPause(
        routePath: KnowledgeRoutes.inbox,
        child: _InboxBody(),
      ),
    );
  }
}

class _InboxBody extends ConsumerWidget {
  const _InboxBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Capture remains the primary Inbox action. AI utilities stay available
    // from the trailing menu without competing with the user's write path.
    return const AppAtmosphere(
      child: AdaptiveContentFrame(
        maxWidth: Breakpoints.readingColumn,
        expandSinglePrimary: true,
        padding: EdgeInsets.zero,
        primary: Column(
          children: [
            _InboxCaptureBar(),
            _InboxTriageStatus(),
            Expanded(child: _NotesList()),
          ],
        ),
      ),
    );
  }
}

class _InboxTriageStatus extends ConsumerWidget {
  const _InboxTriageStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(_knowledgeInboxPendingSuggestionsProvider);
    final count = pending.value ?? 0;
    if (pending.hasError) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s4,
          AppSpacing.s16,
          AppSpacing.s4,
        ),
        child: AppStatusBanner(
          compact: true,
          kind: AppStatusKind.error,
          icon: FLucideIcons.refreshCw,
          message: l10n.knowledgeInboxSuggestionsLoadFailed,
          onPress: () =>
              ref.invalidate(_knowledgeInboxPendingSuggestionsProvider),
        ),
      );
    }
    if (pending.isLoading || count == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s4,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: AppStatusBanner(
        compact: true,
        kind: AppStatusKind.info,
        icon: FLucideIcons.sparkles,
        message: l10n.knowledgeInboxSuggestionsPending(count),
        onPress: () => context.push(KnowledgeRoutes.review),
      ),
    );
  }
}

/// Primary quick-capture target with AI utilities grouped behind one menu.
/// AI actions route through `askAi` conversation mode, scoped to KnowledgeOS
/// tools and prompts:
///
///  - prompt   → empty composer (type a capture or a question freeform)
///  - 查重     → seeds dedupe (agent → find_similar_knowledge → propose_merge)
///  - 本周建议 → seeds suggest (agent → review_knowledge_health → propose_*)
///  - 搜知识   → seeds cross-type search (agent → search_knowledge)
///
/// Conversation prefill (not auto-fired invocation intents) keeps this
/// off the regression-corpus / renderer fixture path while still
/// delivering the full agentic loop on send.
class _InboxCaptureBar extends ConsumerWidget {
  const _InboxCaptureBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final chrome = ref.watch(shellChromeBuildersProvider);
    final actions = [
      DomainAiPromptAction(
        label: l10n.knowledgeAiAskAction,
        icon: FLucideIcons.sparkles,
        onPress: () {
          chrome.openAi(context, ref, prefill: '');
        },
      ),
      DomainAiPromptAction(
        label: l10n.knowledgeAiDedupeAction,
        icon: FLucideIcons.gitMerge,
        onPress: () {
          chrome.openAi(context, ref, prefill: l10n.knowledgeAiDedupePrompt);
        },
      ),
      DomainAiPromptAction(
        label: l10n.knowledgeAiWeeklyAction,
        icon: FLucideIcons.lightbulb,
        onPress: () {
          chrome.openAi(context, ref, prefill: l10n.knowledgeAiWeeklyPrompt);
        },
      ),
      DomainAiPromptAction(
        label: l10n.knowledgeAiSearchAction,
        icon: FLucideIcons.search,
        onPress: () {
          chrome.openAi(context, ref, prefill: l10n.knowledgeAiSearchPrompt);
        },
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: KnowledgePromptSurface(
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: l10n.knowledgeCaptureAction,
                child: AppTappable(
                  onPress: () {
                    showKnowledgeCaptureSheet(context);
                  },
                  child: SizedBox(
                    height: AppSpacing.s40,
                    child: Row(
                      children: [
                        Icon(
                          FLucideIcons.filePlus,
                          size: AppIconSizes.sm,
                          color: colors.primary,
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            l10n.knowledgeCaptureTitle,
                            style: context.bodyCaptionStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s6),
            AppAdaptiveActionMenu(
              title: l10n.knowledgeAiSuggestionsTitle,
              actions: <AppAdaptiveAction>[
                for (final action in actions)
                  AppAdaptiveAction(
                    icon: action.icon,
                    title: action.label,
                    onPress: action.onPress,
                  ),
              ],
              triggerBuilder: (context, openMenu, focusNode) => Focus(
                focusNode: focusNode,
                child: AppIconButton(
                  icon: FLucideIcons.ellipsis,
                  tooltip: l10n.knowledgeAiSuggestionsTitle,
                  onPress: openMenu,
                  size: AppSpacing.s40,
                  iconSize: AppIconSizes.sm,
                  iconColor: colors.primary,
                  surface: AppIconButtonSurface.softPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesList extends ConsumerWidget {
  const _NotesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(knowledgeInboxNotesProvider);
    final l10n = AppLocalizations.of(context);
    // Scope above the loading/data branches: the entrance watermark survives
    // pull-to-refresh, and recycled rows (index <= watermark) never replay
    // the entrance when they scroll back into view.
    return AppEntranceScope(
      child: notesAsync.when(
        loading: () => const AppListPageSkeleton(itemCount: 5),
        error: (e, stackTrace) => AppEmptyState.error(
          title: AppLocalizations.of(context).knowledgeInboxLoadFailedTitle,
          message: userSafeErrorMessage(
            context,
            e,
            stackTrace: stackTrace,
            operation: 'load knowledge inbox',
          ),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(knowledgeInboxNotesProvider),
        ),
        data: (notes) {
          if (notes.isEmpty) {
            return AppRefreshIndicator(
              onRefresh: () => _refreshKnowledgeRepository(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: shellTabContentPadding(context, top: AppSpacing.s8),
                children: [
                  AppEmptyState.inline(
                    icon: FLucideIcons.inbox,
                    title: l10n.knowledgeInboxEmptyTitle,
                    message: l10n.knowledgeInboxEmptyBody,
                  ),
                ],
              ),
            );
          }
          return AppRefreshIndicator(
            onRefresh: () => _refreshKnowledgeRepository(ref),
            child: AppSwipeActionGroup(
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: shellTabContentPadding(
                  context,
                  top: AppSpacing.s8,
                  bottom: AppSpacing.s64,
                ),
                itemCount: notes.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.s8),
                itemBuilder: (context, i) => AppOnceEntrance(
                  index: i,
                  child: _NoteCard(note: notes[i]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> _refreshKnowledgeRepository(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  ref.invalidate(knowledgeInboxNotesProvider);
  await ref.read(knowledgeRepositoryProvider.future);
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note});
  final KnowledgeNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final aiAvailable = ref.watch(knowledgeLlmProfileClientProvider) != null;
    final actions = knowledgeItemActions(
      context: context,
      ref: ref,
      item: note,
      aiAvailable: aiAvailable,
    );
    final title = note.title.isEmpty ? l10n.knowledgeUntitled : note.title;
    Future<void> delete() => deleteKnowledgeEntry(
      context: context,
      ref: ref,
      kind: KnowledgeEntryKind.note,
      id: note.id,
      title: title,
      ownerUserId: note.sync.ownerUserId,
    );
    return AppSwipeActions(
      key: ValueKey<String>('inbox-note-${note.id}'),
      leadingActions: actions.swipeActions,
      trailingActions: <AppSwipeAction>[
        AppSwipeAction(
          id: 'delete',
          icon: FLucideIcons.trash2,
          label: l10n.commonDelete,
          tone: AppSwipeActionTone.danger,
          onPressed: delete,
        ),
      ],
      borderRadius: AppRadius.sm,
      child: KnowledgeSection.item(
        onPress: () => context.pushNamed(
          KnowledgeRouteNames.objectDetail,
          pathParameters: {'kind': 'note', 'id': note.id},
        ),
        title: title,
        trailing: AppAdaptiveActionMenu(
          title: l10n.knowledgeLibraryItemActions,
          actions: [
            ...actions.menuActions,
            AppAdaptiveAction(
              icon: FLucideIcons.trash2,
              title: l10n.commonDelete,
              destructive: true,
              onPress: delete,
            ),
          ],
          triggerBuilder: (context, openMenu, focusNode) => Focus(
            focusNode: focusNode,
            child: AppIconButton(
              icon: FLucideIcons.ellipsis,
              tooltip: l10n.knowledgeLibraryItemActions,
              onPress: openMenu,
              size: AppControlHeights.touchTarget,
              iconSize: AppIconSizes.xs,
            ),
          ),
        ),
        children: [
          if (note.bodyMd.isNotEmpty)
            Text(
              knowledgeExcerpt(note.bodyMd),
              style: context.bodyCaptionStyle,
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
                style: context.captionStyle,
              ),
              if (note.projectTag != null && note.projectTag!.isNotEmpty) ...[
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
                    style: context.captionStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
