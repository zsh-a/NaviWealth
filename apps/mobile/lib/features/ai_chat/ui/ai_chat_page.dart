import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/master_detail_layout.dart';
import '../../../app/route_paths.dart';
import '../../../app/selection_query.dart';
import '../../../core/auth/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../state/chat_controller.dart';
import '../state/route_context_provider.dart';
import 'chat_composer.dart';
import 'message_bubble.dart';
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
  String? _activeSessionId;
  bool _bootstrapped = false;
  String? _lastBootstrappedUserId;
  String? _bootstrappingUserId;
  Object? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _activeSessionId = widget.initialSessionId;
  }

  Future<void> _ensureSession(String ownerUserId) async {
    if (_bootstrapped && _lastBootstrappedUserId == ownerUserId) return;
    if (_bootstrappingUserId == ownerUserId) return;
    _bootstrappingUserId = ownerUserId;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final activeSessionId = _activeSessionId;
      if (activeSessionId != null) {
        final active = await repo.findSession(activeSessionId);
        if (!mounted) return;
        if (active != null && active.ownerUserId == ownerUserId) {
          setState(() {
            _bootstrapped = true;
            _lastBootstrappedUserId = ownerUserId;
            _bootstrapError = null;
          });
          return;
        }
        setState(() => _activeSessionId = null);
      }
      final existing = await repo.listSessions(ownerUserId);
      if (!mounted) return;
      if (existing.isNotEmpty) {
        setState(() {
          _activeSessionId = existing.first.id;
          _bootstrapped = true;
          _lastBootstrappedUserId = ownerUserId;
          _bootstrapError = null;
        });
        return;
      }
      final session = await repo.createSession(ownerUserId: ownerUserId);
      if (!mounted) return;
      setState(() {
        _activeSessionId = session.id;
        _bootstrapped = true;
        _lastBootstrappedUserId = ownerUserId;
        _bootstrapError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapped = false;
        _bootstrapError = e;
      });
    } finally {
      if (_bootstrappingUserId == ownerUserId) {
        _bootstrappingUserId = null;
      }
    }
  }

  Future<void> _newSession(String ownerUserId) async {
    final repo = await ref.read(chatRepositoryProvider.future);
    final session = await repo.createSession(ownerUserId: ownerUserId);
    if (!mounted) return;
    setState(() {
      _activeSessionId = session.id;
    });
  }

  Future<void> _openSessionsSheet(String ownerUserId) async {
    await showFSheet<void>(
      context: context,
      side: FLayout.rtl,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          width: 320,
          child: SessionsPanel(
            activeSessionId: _activeSessionId,
            onSelect: (id) {
              setState(() => _activeSessionId = id);
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
        header: FHeader.nested(title: Text(l10n.aiChatAppBarTitle)),
        childPad: false,
        child: const _LoginRequired(),
      );
    }

    final bootstrappedForUser =
        _bootstrapped && _lastBootstrappedUserId == session.userId;

    if (!bootstrappedForUser &&
        _bootstrappingUserId != session.userId &&
        _bootstrapError == null) {
      // Schedule the bootstrap after build so it doesn't fight the
      // first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureSession(session.userId);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = MasterDetailLayout.shouldUseMasterDetail(width);
        final activeId = bootstrappedForUser ? _activeSessionId : null;
        // At desktop width the URL is the source of truth for the active
        // session — the master-detail surface follows `?selected=`. We
        // still keep `_activeSessionId` populated so the bootstrap path
        // can pick a default.
        final selectedFromQuery = isDesktop && bootstrappedForUser
            ? selectedQueryOf(context)
            : null;
        final desktopActiveId = selectedFromQuery ?? activeId;
        final pendingPane = _bootstrapError == null
            ? const _BootstrappingPane()
            : _BootstrapErrorPane(
                error: _bootstrapError!,
                onRetry: () {
                  setState(() => _bootstrapError = null);
                  _ensureSession(session.userId);
                },
              );

        if (isDesktop) {
          return FScaffold(
            header: FHeader.nested(title: Text(l10n.aiChatAppBarTitle)),
            childPad: false,
            child: MasterDetailLayout(
              master: SessionsPanel(
                activeSessionId: desktopActiveId,
                onSelect: (id) {
                  setState(() => _activeSessionId = id);
                  replaceSelectedQuery(
                    context,
                    path: AppRoutes.ai,
                    selected: id,
                  );
                },
                onNew: () => _newSession(session.userId),
              ),
              detail: desktopActiveId == null
                  ? pendingPane
                  : _ChatPane(sessionId: desktopActiveId),
            ),
          );
        }

        // mobile + tablet: drawer for sessions.
        return FScaffold(
          header: FHeader.nested(
            title: Text(_titleForActive(session.userId, activeId, l10n)),
            suffixes: [
              FHeaderAction(
                icon: const Icon(Icons.history),
                onPress: () => _openSessionsSheet(session.userId),
              ),
              FHeaderAction(
                icon: const Icon(Icons.add),
                onPress: () => _newSession(session.userId),
              ),
            ],
          ),
          childPad: false,
          child: activeId == null
              ? pendingPane
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

class _ChatPane extends ConsumerStatefulWidget {
  const _ChatPane({required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends ConsumerState<_ChatPane> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Motion.fast,
        curve: Motion.standardDecelerate,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      chatMessagesStreamProvider(widget.sessionId),
    );
    final turn = ref.watch(chatControllerProvider(widget.sessionId));

    // Auto-scroll on every new message snapshot.
    ref.listen(chatMessagesStreamProvider(widget.sessionId), (prev, next) {
      next.whenData((_) => _scrollToBottom());
    });

    final l10n = AppLocalizations.of(context);
    final routeCtx = ref.watch(aiRouteContextProvider);
    final systemContext = routeCtx.toSystemContext();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            Expanded(
              child: messagesAsync.when(
                loading: () => const AiChatSkeleton(),
                error: (e, _) =>
                    Center(child: Text(l10n.commonLoadError(e.toString()))),
                data: (messages) => _MessagesList(
                  sessionId: widget.sessionId,
                  messages: messages,
                  scroll: _scroll,
                  onSuggest: (text) => ref
                      .read(chatControllerProvider(widget.sessionId).notifier)
                      .send(
                        text,
                        staleSyncNotice: l10n.aiChatStaleSyncNotice,
                        systemContext: systemContext,
                      ),
                ),
              ),
            ),
            ChatComposer(
              isStreaming: turn.isStreaming,
              isFlushing: turn.isFlushing,
              onSend: (text) {
                ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .send(
                      text,
                      staleSyncNotice: l10n.aiChatStaleSyncNotice,
                      systemContext: systemContext,
                    );
              },
              onCancel: () {
                ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .cancel();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({
    required this.sessionId,
    required this.messages,
    required this.scroll,
    required this.onSuggest,
  });

  final String sessionId;
  final List<ChatMessage> messages;
  final ScrollController scroll;
  final ValueChanged<String> onSuggest;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return _EmptyConversation(onSuggest: onSuggest);
    }
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (_, i) =>
          MessageBubble(sessionId: sessionId, message: messages[i]),
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
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colors.primary.withValues(alpha: 0.85),
                            colors.mutedForeground.withValues(alpha: 0.85),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 28,
                        color: colors.primaryForeground,
                      ),
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
