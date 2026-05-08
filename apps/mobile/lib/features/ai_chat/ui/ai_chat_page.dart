import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final existing = await ref.read(
        chatSessionsStreamProvider(ownerUserId).future,
      );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(authSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: GlassAppBar(title: Text(l10n.aiChatAppBarTitle)),
        body: const _LoginRequired(),
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
          return Scaffold(
            appBar: GlassAppBar(title: Text(l10n.aiChatAppBarTitle)),
            body: MasterDetailLayout(
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
        return Scaffold(
          appBar: GlassAppBar(
            title: Text(_titleForActive(session.userId, activeId, l10n)),
            actions: [
              Builder(
                builder: (ctx) => IconButton(
                  tooltip: l10n.aiChatHistoryTooltip,
                  icon: const Icon(Icons.history),
                  onPressed: () {
                    Scaffold.of(ctx).openEndDrawer();
                  },
                ),
              ),
              IconButton(
                tooltip: l10n.aiChatNewSessionTooltip,
                icon: const Icon(Icons.add),
                onPressed: () => _newSession(session.userId),
              ),
            ],
          ),
          endDrawer: Drawer(
            child: SafeArea(
              child: SessionsPanel(
                activeSessionId: activeId,
                onSelect: (id) {
                  setState(() => _activeSessionId = id);
                  Navigator.of(context).pop();
                },
                onNew: () {
                  Navigator.of(context).pop();
                  _newSession(session.userId);
                },
              ),
            ),
          ),
          body: activeId == null ? pendingPane : _ChatPane(sessionId: activeId),
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
        constraints: const BoxConstraints(maxWidth: Spacing.chatPaneMaxWidth),
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
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s12,
      ),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final suggestions = <String>[
      l10n.aiChatEmptySuggestion1,
      l10n.aiChatEmptySuggestion2,
      l10n.aiChatEmptySuggestion3,
      l10n.aiChatEmptySuggestion4,
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 44, color: cs.primary),
              const SizedBox(height: Spacing.s12),
              Text(
                l10n.aiChatEmptyTitle,
                style: tt.headlineSmall?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: Spacing.s8),
              Text(
                l10n.aiChatEmptyBody,
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.s20),
              Wrap(
                spacing: Spacing.s8,
                runSpacing: Spacing.s8,
                alignment: WrapAlignment.center,
                children: [
                  for (final q in suggestions)
                    ActionChip(label: Text(q), onPressed: () => onSuggest(q)),
                ],
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
    return const Center(child: CircularProgressIndicator());
  }
}

class _BootstrapErrorPane extends StatelessWidget {
  const _BootstrapErrorPane({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: cs.error),
            const SizedBox(height: Spacing.s12),
            Text(
              l10n.commonLoadError(error.toString()),
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: Spacing.s16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.commonRetry),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: Spacing.s12),
            Text(
              l10n.aiChatLoginRequired,
              style: tt.titleMedium?.copyWith(color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
