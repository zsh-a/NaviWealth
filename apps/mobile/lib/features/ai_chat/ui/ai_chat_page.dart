import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/master_detail_layout.dart';
import '../../../app/route_paths.dart';
import '../../../app/selection_query.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/auth/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../state/chat_controller.dart';
import '../state/chat_session_scope.dart';
import '../state/route_context_provider.dart';
import 'ai_action_cards_rail.dart';
import 'ai_context_summary_header.dart';
import 'chat_composer.dart';
import 'chat_conversation_view.dart';
import 'sessions_panel.dart';

/// Top-level "AI 助手" surface (FIR-60).
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
    await showFSheet<void>(
      context: context,
      side: FLayout.rtl,
      builder: (ctx) => AppSheetSurface(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
        safeTop: true,
        child: SizedBox(
          width: 320,
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
    final session = ref.watch(authSessionProvider);
    if (session == null) {
      return FScaffold(
        header: FHeader.nested(
          title: Text(l10n.aiChatAppBarTitle),
          prefixes: [backHeaderAction(context)],
        ),
        childPad: false,
        child: const _LoginRequired(),
      );
    }

    final defaultAsync = ref.watch(
      defaultChatSessionProvider(session.userId),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = MasterDetailLayout.shouldUseMasterDetail(width);
        // At desktop width the URL is the source of truth for the
        // active session — the master-detail surface follows
        // `?selected=`. Explicit selection wins; otherwise the
        // provider resolves the default thread.
        final selectedFromQuery = isDesktop
            ? selectedQueryOf(context)
            : null;
        final activeId =
            _selectedSessionId ??
            selectedFromQuery ??
            defaultAsync.asData?.value;

        Widget pendingPane() {
          if (defaultAsync.hasError) {
            return _BootstrapErrorPane(
              error: defaultAsync.error!,
              onRetry: () => ref.invalidate(
                defaultChatSessionProvider(session.userId),
              ),
            );
          }
          return const _BootstrappingPane();
        }

        if (isDesktop) {
          return FScaffold(
            header: FHeader.nested(
              title: Text(l10n.aiChatAppBarTitle),
              prefixes: [backHeaderAction(context)],
            ),
            childPad: false,
            child: MasterDetailLayout(
              master: SessionsPanel(
                activeSessionId: activeId,
                onSelect: (id) {
                  setState(() => _selectedSessionId = id);
                  replaceSelectedQuery(
                    context,
                    path: AppRoutes.settingsAiHistory,
                    selected: id,
                  );
                },
                onNew: () => _newSession(session.userId),
              ),
              detail: activeId == null
                  ? pendingPane()
                  : _ChatPane(sessionId: activeId),
            ),
          );
        }

        // mobile + tablet: drawer for sessions.
        return FScaffold(
          header: FHeader.nested(
            title: Text(_titleForActive(session.userId, activeId, l10n)),
            prefixes: [backHeaderAction(context)],
            suffixes: [
              FHeaderAction(
                icon: const Icon(Icons.history),
                onPress: () =>
                    _openSessionsSheet(session.userId, activeId),
              ),
              FHeaderAction(
                icon: const Icon(Icons.add),
                onPress: () => _newSession(session.userId),
              ),
            ],
          ),
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
    final l10n = AppLocalizations.of(context);
    final routeCtx = ref.watch(aiRouteContextProvider);
    final systemContext = routeCtx.toSystemContext();

    // "Discovery" chrome (this-month summary + next-action rail) belongs
    // to the *blank* conversation only. Once a thread is underway it is
    // noise competing with the answer, so it collapses entirely and the
    // conversation owns the screen. `false` while the stream is still
    // loading so an existing thread never flashes the chrome.
    final isBlank =
        ref.watch(chatMessagesStreamProvider(sessionId)).asData?.value.isEmpty ??
        false;

    void send(String text) => ref
        .read(chatControllerProvider(sessionId).notifier)
        .send(
          text,
          staleSyncNotice: l10n.aiChatStaleSyncNotice,
          systemContext: systemContext,
        );

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
                loadingBuilder: (_) => const AiChatSkeleton(),
                emptyBuilder: (_) => _EmptyConversation(onSuggest: send),
              ),
            ),
            ChatComposer(
              isStreaming: turn.isStreaming,
              isFlushing: turn.isFlushing,
              onSend: send,
              onCancel: () => ref
                  .read(chatControllerProvider(sessionId).notifier)
                  .cancel(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.onSuggest});

  final ValueChanged<String> onSuggest;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final suggestions = <(String, IconData)>[
      (l10n.aiChatEmptySuggestion1, Icons.calendar_month_outlined),
      (l10n.aiChatEmptySuggestion2, Icons.shield_outlined),
      (l10n.aiChatEmptySuggestion3, Icons.donut_small_outlined),
      (l10n.aiChatEmptySuggestion4, Icons.trending_up),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = Breakpoints.isMobile(constraints.maxWidth);
        final outerPadding = isMobile
            ? const EdgeInsets.all(16)
            : const EdgeInsets.all(24);
        return SingleChildScrollView(
          padding: outerPadding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
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
                          width: 1,
                        ),
                      ),
                      child: const AiSparkle(size: 28),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.aiChatEmptyTitle,
                    textAlign: TextAlign.center,
                    style: context.theme.typography.xl2.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.aiChatEmptyBody,
                    textAlign: TextAlign.center,
                    style: context.theme.typography.sm.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SectionHeader(title: l10n.aiChatEmptySuggestionsHeader),
                  for (var i = 0; i < suggestions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _SuggestionTile(
                      label: suggestions[i].$1,
                      icon: suggestions[i].$2,
                      onTap: () => onSuggest(suggestions[i].$1),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
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
    return FCard.raw(
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: context.theme.typography.sm.copyWith(
                    color: colors.foreground,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 12,
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
          const SizedBox(width: 28, height: 28, child: FCircularProgress()),
          const SizedBox(height: 12),
          Text(
            l10n.aiChatBootstrappingLabel,
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 36,
              color: context.theme.colors.destructive,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.commonLoadError(error.toString()),
              textAlign: TextAlign.center,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.foreground,
              ),
            ),
            const SizedBox(height: 16),
            FButton(
              variant: FButtonVariant.primary,
              onPress: onRetry,
              prefix: const Icon(Icons.refresh, size: 14),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 36,
              color: context.theme.colors.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.aiChatLoginRequired,
              style: context.theme.typography.md.copyWith(
                color: context.theme.colors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
