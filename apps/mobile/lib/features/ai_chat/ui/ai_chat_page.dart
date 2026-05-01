import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../state/chat_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _activeSessionId = widget.initialSessionId;
  }

  Future<void> _ensureSession(String ownerUserId) async {
    if (_activeSessionId != null) return;
    if (_lastBootstrappedUserId == ownerUserId) return;
    _lastBootstrappedUserId = ownerUserId;
    final repo = await ref.read(chatRepositoryProvider.future);
    final existing = await ref.read(
      chatSessionsStreamProvider(ownerUserId).future,
    );
    if (!mounted) return;
    if (existing.isNotEmpty) {
      setState(() {
        _activeSessionId = existing.first.id;
        _bootstrapped = true;
      });
      return;
    }
    final session = await repo.createSession(ownerUserId: ownerUserId);
    if (!mounted) return;
    setState(() {
      _activeSessionId = session.id;
      _bootstrapped = true;
    });
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
    final session = ref.watch(authSessionReaderProvider)();
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI 助手')),
        body: const _LoginRequired(),
      );
    }

    if (!_bootstrapped) {
      // Schedule the bootstrap after build so it doesn't fight the
      // first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureSession(session.userId);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = Breakpoints.isDesktop(width);
        final activeId = _activeSessionId;

        if (isDesktop) {
          return Scaffold(
            appBar: AppBar(title: const Text('AI 助手')),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: Spacing.sessionsPanel,
                  child: SessionsPanel(
                    activeSessionId: activeId,
                    onSelect: (id) => setState(() => _activeSessionId = id),
                    onNew: () => _newSession(session.userId),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: activeId == null
                      ? const _BootstrappingPane()
                      : _ChatPane(sessionId: activeId),
                ),
              ],
            ),
          );
        }

        // mobile + tablet: drawer for sessions.
        return Scaffold(
          appBar: AppBar(
            title: Text(_titleForActive(session.userId, activeId)),
            actions: [
              Builder(
                builder: (ctx) => IconButton(
                  tooltip: '历史对话',
                  icon: const Icon(Icons.history),
                  onPressed: () {
                    Scaffold.of(ctx).openEndDrawer();
                  },
                ),
              ),
              IconButton(
                tooltip: '新建对话',
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
          body: activeId == null
              ? const _BootstrappingPane()
              : _ChatPane(sessionId: activeId),
        );
      },
    );
  }

  String _titleForActive(String userId, String? id) {
    if (id == null) return 'AI 助手';
    final sessionsAsync = ref.watch(chatSessionsStreamProvider(userId));
    return sessionsAsync.maybeWhen(
      data: (sessions) {
        for (final s in sessions) {
          if (s.id == id) return s.title;
        }
        return 'AI 助手';
      },
      orElse: () => 'AI 助手',
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Spacing.chatPaneMaxWidth),
        child: Column(
          children: [
            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败：$e')),
                data: (messages) => _MessagesList(
                  sessionId: widget.sessionId,
                  messages: messages,
                  scroll: _scroll,
                  onSuggest: (text) => ref
                      .read(chatControllerProvider(widget.sessionId).notifier)
                      .send(text),
                ),
              ),
            ),
            ChatComposer(
              isStreaming: turn.isStreaming,
              isFlushing: turn.isFlushing,
              onSend: (text) {
                ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .send(text);
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
      itemBuilder: (_, i) => MessageBubble(
        sessionId: sessionId,
        message: messages[i],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.onSuggest});

  final ValueChanged<String> onSuggest;

  static const _suggestions = <String>[
    '我最近三个月赚了多少？',
    '帮我看看持仓里风险最高的资产。',
    '我的行业分布是怎样的？',
    '从开户到现在我的 XIRR 是多少？',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
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
                '你的财务助手',
                style: tt.headlineSmall?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: Spacing.s8),
              Text(
                '基于你的持仓与交易回答问题。所有金额来自你本地同步的账本，模型不会自行计算关键数字。',
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.s20),
              Wrap(
                spacing: Spacing.s8,
                runSpacing: Spacing.s8,
                alignment: WrapAlignment.center,
                children: [
                  for (final q in _suggestions)
                    ActionChip(
                      label: Text(q),
                      onPressed: () => onSuggest(q),
                    ),
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

class _LoginRequired extends StatelessWidget {
  const _LoginRequired();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: Spacing.s12),
            Text(
              '请先登录后再使用 AI 助手',
              style: tt.titleMedium?.copyWith(color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
