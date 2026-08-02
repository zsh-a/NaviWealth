/// KnowledgeOS Inbox tab (`docs/domains/knowledgeos-domain.md` §5).
///
/// Renders captured Notes. The Inbox action now supports Auto capture
/// plus explicit type selection: quick Notes remain one tap away, while
/// Routine / Decision / Principle / Assumption / Concept / Experiment
/// can be marked at capture time.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_widgets.dart';
import 'knowledge_capture_sheet.dart';

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
    return ShellTabScaffold(
      title: l10n.knowledgeInboxTitle,
      directActionBudget: 1,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.knowledgeCaptureAction,
          onPress: () => showKnowledgeCaptureSheet(context),
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
    // The Inbox is the KnowledgeOS "AI 助理" front door: the bar stays
    // pinned above the note list (visible even while loading / empty) so
    // add / query / dedupe / suggest are always one tap away.
    return const AppAtmosphere(
      child: AdaptiveContentFrame(
        maxWidth: Breakpoints.readingColumn,
        expandSinglePrimary: true,
        padding: EdgeInsets.zero,
        primary: Column(
          children: [
            _AiAssistantBar(),
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
    final aiAvailable = ref.watch(deviceLlmAvailableProvider);
    final pending = ref.watch(_knowledgeInboxPendingSuggestionsProvider);
    final count = pending.value ?? 0;
    if (aiAvailable && count == 0 && !pending.isLoading && !pending.hasError) {
      return const SizedBox.shrink();
    }
    final message = count > 0
        ? l10n.knowledgeInboxSuggestionsPending(count)
        : aiAvailable
        ? l10n.knowledgeInboxSuggestionsLoading
        : l10n.knowledgeInboxAiUnavailable;
    final route = count > 0 ? KnowledgeRoutes.review : SettingsRoutes.aiLlm;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s4,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: AppStatusBanner(
        compact: true,
        kind: count > 0 ? AppStatusKind.info : AppStatusKind.neutral,
        icon: count > 0 ? FLucideIcons.sparkles : FLucideIcons.cpu,
        message: message,
        onPress: pending.hasError ? null : () => context.push(route),
      ),
    );
  }
}

/// The agent entry: a compact ask/capture target + icon quick actions.
/// Each routes through `askAi` conversation mode, which (on the knowledge
/// route) opens the device agent loop scoped to KnowledgeOS tools + prompt
/// with the composer seeded. The user sends; the agent then chains the
/// right tools:
///
///  - prompt   → empty composer (type a capture or a question freeform)
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
    final colors = context.theme.colors;
    final chrome = ref.watch(shellChromeBuildersProvider);
    final actions = [
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
                label: l10n.knowledgeAiPromptHint,
                child: AppTappable(
                  onPress: () {
                    chrome.openAi(context, ref, prefill: '');
                  },
                  child: SizedBox(
                    height: AppSpacing.s40,
                    child: Row(
                      children: [
                        Icon(
                          FLucideIcons.sparkles,
                          size: AppIconSizes.sm,
                          color: colors.primary,
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            l10n.knowledgeAiPromptHint,
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
    return notesAsync.when(
      loading: () => const KnowledgeLoadingState(),
      error: (e, stackTrace) => KnowledgeErrorState(
        title: AppLocalizations.of(context).knowledgeInboxLoadFailedTitle,
        message: userSafeErrorMessage(
          context,
          e,
          stackTrace: stackTrace,
          operation: 'load knowledge inbox',
        ),
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
                KnowledgeEmptyState(
                  icon: FLucideIcons.inbox,
                  title: l10n.knowledgeInboxEmptyTitle,
                  message: l10n.knowledgeInboxEmptyBody,
                  density: KnowledgeStateDensity.section,
                ),
              ],
            ),
          );
        }
        return AppRefreshIndicator(
          onRefresh: () => _refreshKnowledgeRepository(ref),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: shellTabContentPadding(
              context,
              top: AppSpacing.s8,
              bottom: AppSpacing.s64,
            ),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, i) => _NoteCard(note: notes[i]),
          ),
        );
      },
    );
  }
}

Future<void> _refreshKnowledgeRepository(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  ref.invalidate(knowledgeInboxNotesProvider);
  await ref.read(knowledgeRepositoryProvider.future);
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final KnowledgeNote note;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return KnowledgeSection.item(
      onPress: () => context.pushNamed(
        KnowledgeRouteNames.objectDetail,
        pathParameters: {'kind': 'note', 'id': note.id},
      ),
      title: note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
      children: [
        if (note.bodyMd.isNotEmpty)
          Text(knowledgeExcerpt(note.bodyMd), style: context.bodyCaptionStyle),
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
    );
  }
}
