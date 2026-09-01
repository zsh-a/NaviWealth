import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/composition/ai_context.dart';

import '../../../core/ai/composition/ai_context_summary.dart';
import '../../../core/ai/composition/assistant_route_paths.dart';
import '../../../core/ai/session/interaction_state.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/shell/auth_route_paths.dart';
import '../../../core/shell/master_detail_layout.dart';
import '../../../core/shell/selection_query.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../domain/chat_turn_metadata.dart';
import '../state/chat_controller.dart';
import '../state/chat_session_scope.dart';
import 'ai_action_cards_rail.dart';
import 'ai_context_summary_header.dart';
import 'chat_composer.dart';
import 'chat_conversation_view.dart';
import 'sessions/sessions_panel.dart';

/// Top-level "AI 助手" surface.
///
/// Layout adapts at the [Breakpoints.mobile] / local content
/// boundaries:
///
///  - mobile (< 600px): single-column conversation, sessions accessible
///    via a sheet.
///  - medium (600–1024px): same single-column conversation but with the
///    sessions in a slim end sheet triggered from the AppBar.
///  - roomy content (>= 1024px): permanent two-pane Row — sessions on the
///    left, conversation on the right.
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key, this.initialSessionId});

  final String? initialSessionId;

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  /// The session the user explicitly selected (sessions panel / "+").
  /// `null` ⇒ fall back to [defaultChatSessionProvider].
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
    final size = MediaQuery.sizeOf(context);
    final isMobile = Breakpoints.isMobile(size.width);
    await showAppFormSheet<void>(
      context: context,
      builder: (ctx) => AppSheetSurface(
        borderRadius: isMobile
            ? const BorderRadius.vertical(top: Radius.circular(AppRadius.lg))
            : const BorderRadius.horizontal(
                left: Radius.circular(AppRadius.lg),
              ),
        safeTop: true,
        child: SizedBox(
          width: isMobile ? size.width : AppControlWidths.aiSessionsPanel,
          height: isMobile ? size.height * 0.92 : null,
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
      builder: (context, constraints) {
        final isDesktop = MasterDetailLayout.shouldUseMasterDetail(
          constraints.maxWidth,
        );
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
          // First load hydrates from the local store in well under a frame
          // budget — mirror the resolved conversation with the shared chat
          // skeleton instead of a context-free spinner.
          return const AiChatSkeleton();
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
                    path: AssistantRoutes.home,
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

        return AppPageScaffold(
          title: _titleForActive(userId, activeId, l10n),
          actions: [
            AppHeaderAction(
              semanticsLabel: l10n.aiChatHistoryTooltip,
              icon: const Icon(FLucideIcons.history),
              onPress: () => _openSessionsSheet(userId, activeId),
            ),
            AppHeaderAction(
              semanticsLabel: l10n.aiChatNewSessionTooltip,
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
    final messagesAsync = ref.watch(chatMessagesStreamProvider(sessionId));
    final routeCtx = ref.watch(aiContextProvider);
    final systemContext = routeCtx.toSystemContext();

    void send(String text) => ref
        .read(chatControllerProvider(sessionId).notifier)
        .send(text, systemContext: systemContext);

    void sendWithOrigin(String text, InteractionInputOrigin origin) => ref
        .read(chatControllerProvider(sessionId).notifier)
        .send(
          text,
          systemContext: systemContext,
          turnMetadata: ChatTurnMetadata(inputOrigin: origin),
        );

    void editResend(String messageId, String text) => ref
        .read(chatControllerProvider(sessionId).notifier)
        .editAndResend(
          messageId: messageId,
          newContent: text,
          systemContext: systemContext,
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.readingColumn),
        child: Column(
          children: [
            // Keep discovery chrome out of the blank-state suggestion list.
            // Once a conversation has started, surface the latest domain
            // context and agent-owned next actions above the timeline so the
            // user can continue from current reality instead of composing a
            // prompt from scratch.
            _AiChatContextRail(
              visible: messagesAsync.maybeWhen(
                data: (messages) => messages.isNotEmpty,
                orElse: () => false,
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotionPolicy.duration(context, Motion.medium),
                switchInCurve: Motion.standardDecelerate,
                switchOutCurve: Motion.standardAccelerate,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: KeyedSubtree(
                  key: ValueKey(sessionId),
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
              ),
            ),
            ChatComposer(
              sessionId: sessionId,
              isStreaming: turn.isStreaming,
              isVoiceActive: turn.voiceActive,
              voiceStarting: turn.voiceStarting,
              canStartVoice: turn.canStartVoice,
              voiceCapabilities: turn.voiceCapabilities,
              voiceCapsuleVisible: turn.voiceCapsuleVisible,
              voicePhase: turn.voicePhase,
              voiceTranscript: turn.voiceTranscript,
              voiceErrorCode: turn.voiceErrorCode,
              voiceOutputErrorCode: turn.voiceOutputErrorCode,
              voiceInputLane: turn.voiceInputLane,
              voiceOutputLane: turn.voiceOutputLane,
              onStartVoice: () => ref
                  .read(chatControllerProvider(sessionId).notifier)
                  .startVoice(systemContext: systemContext),
              onStopVoice: () => ref
                  .read(chatControllerProvider(sessionId).notifier)
                  .stopVoice(),
              onCancelVoice: () => ref
                  .read(chatControllerProvider(sessionId).notifier)
                  .cancelVoice(),
              onVoiceRetry: () => ref
                  .read(chatControllerProvider(sessionId).notifier)
                  .startVoice(systemContext: systemContext),
              onVoiceSwitchToText: () => ref
                  .read(chatControllerProvider(sessionId).notifier)
                  .cancelVoice(),
              onSend: send,
              onSendWithOrigin: sendWithOrigin,
              onEditResend: editResend,
              onCancel: () =>
                  ref.read(chatControllerProvider(sessionId).notifier).cancel(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiChatContextRail extends StatelessWidget {
  const _AiChatContextRail({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotionPolicy.duration(context, Motion.fast),
      curve: Motion.standardDecelerate,
      alignment: Alignment.topCenter,
      child: visible
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [AiContextSummaryHeader(), AiActionCardsRail()],
            )
          : const SizedBox(width: double.infinity),
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
              constraints: const BoxConstraints(
                maxWidth: Breakpoints.formColumn,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.s32),
                  const Center(child: AiSparkle(active: true, size: 18)),
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
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s24),
                    for (var i = 0; i < suggestions.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.s8),
                      _SuggestionTile(
                        label: suggestions[i].$1,
                        icon: suggestions[i].$2,
                        onTap: () => onSuggest(suggestions[i].$1),
                      ),
                    ],
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

/// Up to 3 suggestion tiles. Dynamic facts win; evergreen defaults fill.
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

  if (out.length > 2) out.removeRange(2, out.length);

  final defaults = <(String, IconData)>[
    (l10n.aiChatEmptySuggestion1, FLucideIcons.calendar),
    (l10n.aiChatEmptySuggestion2, FLucideIcons.shield),
    (l10n.aiChatEmptySuggestion3, FLucideIcons.chartPie),
  ];
  final existing = {for (final s in out) s.$1};
  for (final d in defaults) {
    if (out.length >= 3) break;
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
    return AppTappable(
      onPress: onTap,
      child: SoftCard.flat(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.s12,
        ),
        borderRadius: AppRadius.md,
        child: Row(
          children: [
            Container(
              width: AppSpacing.s32,
              height: AppSpacing.s32,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: AppOpacity.subtle),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
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
              textAlign: TextAlign.center,
              style: context.theme.typography.body.md.copyWith(
                color: context.theme.colors.foreground,
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            AppActionButton(
              mainAxisSize: MainAxisSize.min,
              onPress: () => context.go(AuthRoutes.login),
              prefix: const Icon(FLucideIcons.logIn, size: AppIconSizes.xs),
              child: Text(l10n.authLoginSubmit),
            ),
          ],
        ),
      ),
    );
  }
}
