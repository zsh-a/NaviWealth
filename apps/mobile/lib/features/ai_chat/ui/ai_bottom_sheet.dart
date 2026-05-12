/// Wave 33 — `AiBottomSheetShell` + `showAiBottomSheet`.
///
/// **The default surface for any [AiIntentInvocation]**. Renders a
/// modal bottom sheet over the user's current page (per §5.4 doc rule:
/// "AI 进入用户当前页面"); a "expand to chat" button hands the
/// underlying session off to `/ai` when the user wants a full
/// conversation. Auto-upgrades to full-screen modal route when the
/// viewport is too short.
///
/// Hard constraints (§5.8):
///   - Only entry point for AI from outside the chat tab
///   - Reuses `ChatRepository.sendMessage` — no separate runtime path
///   - Attaches `AiIntentInvocation.toTraceJson()` to AiTrace
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/intent/intent.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/auth/providers.dart';
import '../data/providers.dart';
import 'message_bubble.dart';

/// Open the AI bottom sheet for the given [invocation]. Use this helper
/// at every call site — never construct `AiBottomSheetShell` directly,
/// never push `/ai` for non-conversation entry points.
Future<void> showAiBottomSheet(
  BuildContext context, {
  required AiIntentInvocation invocation,
  String? objectLabel,
}) {
  final viewportHeight = MediaQuery.of(context).size.height;
  // §5.4 fallback rule: short viewport → full-screen modal route
  // rather than a cramped sheet (old Android landscape, etc.).
  if (viewportHeight < 500) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Dialog.fullscreen(
          child: AiBottomSheetShell(
            invocation: invocation,
            objectLabel: objectLabel,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => AiBottomSheetShell(
        invocation: invocation,
        objectLabel: objectLabel,
        scrollController: controller,
      ),
    ),
  );
}

class AiBottomSheetShell extends ConsumerStatefulWidget {
  const AiBottomSheetShell({
    super.key,
    required this.invocation,
    this.objectLabel,
    this.scrollController,
  });

  final AiIntentInvocation invocation;

  /// Human label for the object (e.g. "Netflix 订阅", "投资账户")—used
  /// to fill `{{object_label}}` in the prompt template and as the
  /// sheet's context header.
  final String? objectLabel;

  final ScrollController? scrollController;

  @override
  ConsumerState<AiBottomSheetShell> createState() => _AiBottomSheetShellState();
}

class _AiBottomSheetShellState extends ConsumerState<AiBottomSheetShell> {
  String? _sessionId;
  bool _kicked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
  }

  Future<void> _kick() async {
    if (_kicked) return;
    _kicked = true;
    final auth = ref.read(authSessionProvider);
    if (auth == null) {
      setState(() => _error = '需要登录后才能使用 AI 功能');
      return;
    }
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      // Wave 33: spin up a real chat session backed by ChatHistoryStore
      // so "expand to chat" can take over without rebuilding state.
      // Title encodes the intent for sidebar legibility.
      final desc = lookupIntent(widget.invocation.intent);
      final title = desc != null
          ? '${desc.labelZh} · ${widget.objectLabel ?? widget.invocation.object?.type ?? "AI"}'
          : (widget.objectLabel ?? 'AI');
      final session = await repo.createSession(
        ownerUserId: auth.userId,
        title: title,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = session.id;
      });
      // Fire the prompt. The stream writes into the chat store; we
      // re-render via chatMessagesStreamProvider.
      final prompt = renderPromptFor(
        widget.invocation,
        objectLabel: widget.objectLabel,
      );
      unawaited(
        repo.sendMessage(
          sessionId: session.id,
          ownerUserId: auth.userId,
          content: prompt,
          invocationTrace: widget.invocation.toTraceJson(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(invocation: widget.invocation, objectLabel: widget.objectLabel),
          const Divider(height: 1),
          Expanded(child: _body(context)),
          if (_sessionId != null) ...[
            const Divider(height: 1),
            _Footer(
              onExpand: () => _expandToChat(context),
              onDismiss: () => Navigator.of(context).maybePop(),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final sessionId = _sessionId;
    if (sessionId == null) {
      // Wave 37 — skeleton message instead of a generic spinner. The
      // sheet has already opened with the invocation context visible
      // in the header, so the body should feel "AI is about to talk"
      // not "loading…". Three muted bars sized like a typical bubble
      // are enough to anchor the eye.
      return const _BodySkeleton();
    }
    final msgsAsync = ref.watch(chatMessagesStreamProvider(sessionId));
    return msgsAsync.when(
      data: (msgs) {
        if (msgs.isEmpty) {
          return const SizedBox.shrink();
        }
        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: msgs.length,
          itemBuilder: (context, i) => MessageBubble(
            sessionId: sessionId,
            message: msgs[i],
            invocationIntent: widget.invocation.intent,
            onReplyChip: (chip) => _sendChip(sessionId, chip),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('对话渲染失败: $e'),
      ),
    );
  }

  Future<void> _sendChip(String sessionId, String chip) async {
    final auth = ref.read(authSessionProvider);
    if (auth == null) return;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      unawaited(
        repo.sendMessage(
          sessionId: sessionId,
          ownerUserId: auth.userId,
          content: chip,
          // Same invocation tag as the original turn — the trace
          // attribution carries through follow-up chip taps so the
          // transparency page can group them.
          invocationTrace: widget.invocation.toTraceJson(),
        ),
      );
    } catch (_) {
      // Best-effort: chip taps are non-critical.
    }
  }

  void _expandToChat(BuildContext context) {
    final sid = _sessionId;
    if (sid == null) return;
    Navigator.of(context).pop();
    // §5.4 expand path: navigate to /ai with the existing session id.
    // The query parameter is what the chat page reads when picking the
    // selected session on master-detail layouts.
    context.go('${AppRoutes.ai}?selected=$sid');
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.invocation, this.objectLabel});
  final AiIntentInvocation invocation;
  final String? objectLabel;

  @override
  Widget build(BuildContext context) {
    final desc = lookupIntent(invocation.intent);
    // Wave 36 — single inline header row: sparkle + intent label +
    // middot + object label. Replaces the two-line block so context
    // stays visible while the sheet body scrolls.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          const AiSparkle(),
          const SizedBox(width: 8),
          Flexible(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: desc?.labelZh ?? 'AI',
                    style: AiType.label(context),
                  ),
                  if (objectLabel != null) ...[
                    TextSpan(
                      text: '  ·  ',
                      style: AiType.meta(context),
                    ),
                    TextSpan(
                      text: objectLabel!,
                      style: AiType.meta(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wave 37 — placeholder shape that materialises into the first
/// assistant turn. Three rows of muted bars sized roughly like a chat
/// bubble; pulses subtly with [AiMotion.medium] so the eye knows
/// something is coming.
class _BodySkeleton extends StatefulWidget {
  const _BodySkeleton();

  @override
  State<_BodySkeleton> createState() => _BodySkeletonState();
}

class _BodySkeletonState extends State<_BodySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          // Lerp between 0.35 and 0.65 alpha — barely perceptible.
          final alpha = 0.35 + 0.30 * t;
          final color = AiTone.surfaceTint(context).withValues(alpha: alpha);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(color, widthFactor: 0.85),
              const SizedBox(height: 8),
              _bar(color, widthFactor: 0.65),
              const SizedBox(height: 8),
              _bar(color, widthFactor: 0.45),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(Color color, {required double widthFactor}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onExpand, required this.onDismiss});
  final VoidCallback onExpand;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('关闭'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onExpand,
            icon: const Icon(Icons.open_in_full, size: 16),
            label: const Text('展开对话'),
          ),
        ],
      ),
    );
  }
}

