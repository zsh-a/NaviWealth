import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/composition/ai_context.dart';

import '../../../core/ai/composition/ai_context_summary.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/shell/master_detail_layout.dart';
import '../../../core/shell/selection_query.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../state/chat_controller.dart';
import '../state/chat_session_scope.dart';
import 'ai_action_cards_rail.dart';
import 'ai_context_summary_header.dart';
import 'chat_composer.dart';
import 'chat_conversation_view.dart';
import 'llm_profile_chip.dart';
import 'sessions/sessions_panel.dart';

/// Top-level "AI 助手" surface.
///
/// Layout adapts at the [Breakpoints.mobile] / [Breakpoints.desktop]
/// boundaries:
///
///  - mobile (< 600px): single-column conversation, sessions accessible
///    via a [Drawer].
///  - tablet (600–1240px): same single-column conversation but with the
///    sessions in a slim end drawer triggered from the AppBar.
///  - desktop (>= 1240px): permanent two-pane Row — sessions on the
///    left, conversation on the right.
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key, this.initialSessionId});

  final String? initialSessionId;

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  /// The session the user explicitly selected (sessions panel / "+").
  /// `null` ⇒ fall back to [defaultChatSessionProvider]. Session
  /// *resolution* (resume newest / create first) now lives in that
  /// provider; this is purely "which thread is the user looking at".
  String? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    _selectedSessionId = widget.initialSessionId;
  }

  Future<void> _newSession(String ownerUserId) async {
    final repo = await ref.read(chatRepositoryProvider.future);
    final session = await repo.createSession(ownerUserId: ownerUserId);
    if (!mounted) return;
    setState(() => _selectedSessionId = session.id);
  }

  Future<void> _openSessionsSheet(String ownerUserId, String? activeId) async {
    await showAppFormSheet<void>(
      context: context,
      builder: (ctx) => AppSheetSurface(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(AppRadius.lg),
        ),
        safeTop: true,
        child: SizedBox(
          width: AppControlWidths.aiSessionsPanel,
          child: SessionsPanel(
            activeSessionId: activeId,
            onSelect: (id) {
              setState(() => _selectedSessionId = id);
              Navigator.of(ctx).pop();
            },
            onNew: () async {
              Navigator.of(ctx).pop();
              await _newSession(ownerUserId);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Device-only AI is available in local-only mode too — scope by the
    // active user id ([kLocalOnlyUserId] when account-less) instead of a
    // cloud session. `null` only while auth is still settling.
    final userId = ref.watch(activeUserIdProvider);
    if (userId == null) {
      return AppPageScaffold(
        title: l10n.aiChatAppBarTitle,
        childPad: false,
        child: const _LoginRequired(),
      );
    }

    final defaultAsync = ref.watch(defaultChatSessionProvider(userId));

    return LayoutBuilder(
      builder: (context, _) {
        final isDesktop = MasterDetailLayout.shouldUseMasterDetail(
          MediaQuery.sizeOf(context).width,
        );
        // `?selected=` is used by expand-from-sheet and by the desktop
        // master-detail list. Explicit in-page selection wins; otherwise the
        // provider resolves the default thread.
        final selectedFromQuery = selectedQueryOf(context);
        final activeId =
            _selectedSessionId ??
            selectedFromQuery ??
            defaultAsync.asData?.value;

        Widget pendingPane() {
          if (defaultAsync.hasError) {
            return _BootstrapErrorPane(
              error: defaultAsync.error!,
              onRetry: () => ref.invalidate(defaultChatSessionProvider(userId)),
            );
          }
          return const _BootstrappingPane();
        }

        if (isDesktop) {
          return AppPageScaffold(
            title: l10n.aiChatAppBarTitle,
            childPad: false,
            child: MasterDetailLayout(
              master: SessionsPanel(
                activeSessionId: activeId,
                onSelect: (id) {
                  setState(() => _selectedSessionId = id);
                  replaceSelectedQuery(
                    context,
                    path: SettingsRoutes.aiHistory,
                    selected: id,
                  );
                },
                onNew: () => _newSession(userId),
              ),
              detail: activeId == null
                  ? pendingPane()
                  : _ChatPane(sessionId: activeId),
            ),
          );
        }

        // mobile + tablet: drawer for sessions.
        return AppPageScaffold(
          title: _titleForActive(userId, activeId, l10n),
          actions: [
            FHeaderAction(
              icon: const Icon(FLucideIcons.history),
              onPress: () => _openSessionsSheet(userId, activeId),
            ),
            FHeaderAction(
              icon: const Icon(FLucideIcons.plus),
              onPress: () => _newSession(userId),
            ),
          ],
          childPad: false,
          child: activeId == null
              ? pendingPane()
              : _ChatPane(sessionId: activeId),
        );
      },
    );
  }

  String _titleForActive(String userId, String? id, AppLocalizations l10n) {
    if (id == null) return l10n.aiChatAppBarTitle;
    final sessionsAsync = ref.watch(chatSessionsStreamProvider(userId));
    return sessionsAsync.maybeWhen(
      data: (sessions) {
        for (final s in sessions) {
          if (s.id == id) return s.title;
        }
        return l10n.aiChatAppBarTitle;
      },
      orElse: () => l10n.aiChatAppBarTitle,
    );
  }
}

class _ChatPane extends ConsumerWidget {
  const _ChatPane({required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = ref.watch(chatControllerProvider(sessionId));
    final routeCtx = ref.watch(aiContextProvider);
    final systemContext = routeCtx.toSystemContext();

    // "Discovery" chrome (this-month summary + next-action rail) belongs
    // to the *blank* conversation only. Once a thread is underway it is
    // noise competing with the answer, so it collapses entirely and the
    // conversation owns the screen. `false` while the stream is still
    // loading so an existing thread never flashes the chrome.
    final isBlank =
        ref
            .watch(chatMessagesStreamProvider(sessionId))
            .asData
            ?.value
            .isEmpty ??
        false;

    void send(String text) => ref
        .read(chatControllerProvider(sessionId).notifier)
        .send(text, systemContext: systemContext);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            if (isBlank) ...[
              const AiContextSummaryHeader(),
              const AiActionCardsRail(),
            ],
            Expanded(
              child: ChatConversationView(
                sessionId: sessionId,
                onDecisionSelect: (selection) {
                  ref
                      .read(chatControllerProvider(sessionId).notifier)
                      .chooseDecision(
                        messageId: selection.messageId,
                        toolInvocationId: selection.toolInvocationId,
                        selection: DecisionSelection(
                          optionId: selection.option.id,
                          label: selection.option.label,
                          reply: selection.reply,
                          selectedAt: DateTime.now().toUtc(),
                        ),
                        systemContext: systemContext,
                      );
                },
                loadingBuilder: (_) => const AiChatSkeleton(),
                emptyBuilder: (_) => _EmptyConversation(onSuggest: send),
              ),
            ),
            const LlmProfileChip(),
            ChatComposer(
              isStreaming: turn.isStreaming,
              onSend: send,
              onCancel: () =>
                  ref.read(chatControllerProvider(sessionId).notifier).cancel(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends ConsumerWidget {
  const _EmptyConversation({required this.onSuggest});

  final ValueChanged<String> onSuggest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(aiContextSummaryProvider)(l10n);
    final suggestions = _composeSuggestions(l10n, summary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = Breakpoints.isMobile(constraints.maxWidth);
        final outerPadding = isMobile
            ? const EdgeInsets.all(AppSpacing.s16)
            : const EdgeInsets.all(AppSpacing.s24);
        return SingleChildScrollView(
          padding: outerPadding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.s24),
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AiTone.surfaceTint(context),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AiTone.outline(context),
                          width: AppStroke.hairline,
                        ),
                      ),
                      child: const AiSparkle(size: 28),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    l10n.aiChatEmptyTitle,
                    textAlign: TextAlign.center,
                    style: context.displayTitleStyle.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    l10n.aiChatEmptyBody,
                    textAlign: TextAlign.center,
                    style: context.bodyCaptionStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  SectionHeader(title: l10n.aiChatEmptySuggestionsHeader),
                  for (var i = 0; i < suggestions.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.s8),
                    _SuggestionTile(
                      label: suggestions[i].$1,
                      icon: suggestions[i].$2,
                      onTap: () => onSuggest(suggestions[i].$1),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Build the 4 empty-state tiles. Dynamic suggestions sourced from
/// [AiContextSummary.facts] take priority (up to 3 slots) so the
/// first thing the user sees reflects what's actually happening
/// across the active domains right now; static fallbacks fill the
/// rest so the surface never shrinks below 4 tiles.
List<(String, IconData)> _composeSuggestions(
  AppLocalizations l10n,
  AiContextSummary s,
) {
  final out = <(String, IconData)>[];

  for (final fact in s.facts) {
    final suggestion = fact.suggestion;
    if (suggestion != null) {
      out.add((suggestion, fact.icon));
    }
  }

  // Cap dynamic suggestions at 3 so a static "evergreen" question is
  // always present — helps when the dynamic ones all point at the same
  // kind of follow-up (e.g. anomaly + maturity both feel reactive).
  if (out.length > 3) out.removeRange(3, out.length);

  final defaults = <(String, IconData)>[
    (l10n.aiChatEmptySuggestion1, FLucideIcons.calendar),
    (l10n.aiChatEmptySuggestion2, FLucideIcons.shield),
    (l10n.aiChatEmptySuggestion3, FLucideIcons.chartPie),
    (l10n.aiChatEmptySuggestion4, FLucideIcons.trendingUp),
  ];
  final existing = {for (final s in out) s.$1};
  for (final d in defaults) {
    if (out.length >= 4) break;
    if (existing.contains(d.$1)) continue;
    out.add(d);
  }
  return out;
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: AppOpacity.light),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: AppIconSizes.sm, color: colors.primary),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  label,
                  style: context.theme.typography.body.sm.copyWith(
                    color: colors.foreground,
                  ),
                ),
              ),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.xs,
                color: colors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BootstrappingPane extends StatelessWidget {
  const _BootstrappingPane();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: AppSpacing.s28,
            height: AppSpacing.s28,
            child: FCircularProgress(),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(l10n.aiChatBootstrappingLabel, style: context.captionStyle),
        ],
      ),
    );
  }
}

class _BootstrapErrorPane extends StatelessWidget {
  const _BootstrapErrorPane({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.circleAlert,
              size: 36,
              color: context.theme.colors.destructive,
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              userSafeErrorMessage(context, error),
              textAlign: TextAlign.center,
              style: context.theme.typography.body.sm.copyWith(
                color: context.theme.colors.foreground,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            FButton(
              variant: FButtonVariant.primary,
              onPress: onRetry,
              prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginRequired extends StatelessWidget {
  const _LoginRequired();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.lock,
              size: 36,
              color: context.theme.colors.mutedForeground,
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.aiChatLoginRequired,
              style: context.theme.typography.body.md.copyWith(
                color: context.theme.colors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
