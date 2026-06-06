import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import 'message_bubble.dart';

/// The conversation timeline — message list + follow-scroll + the
/// loading / error / empty states — shared by every AI chat surface
/// (full page, slide-up sheet, intent bottom sheet).
///
/// Before this existed, `_ChatPaneState`, `_SheetMessagesState` and the
/// bottom-sheet body each re-implemented this independently and had
/// already drifted: the bottom sheet, for instance, never followed the
/// stream to the bottom. Routing all three through one widget keeps
/// follow-scroll, message animation and reply-chip wiring identical and
/// makes a message-level affordance (copy / retry / feedback) a
/// one-place change instead of three.
///
/// The host owns chrome around the timeline (headers, composer,
/// summary cards); this widget owns only the scrollable conversation.
class ChatConversationView extends ConsumerStatefulWidget {
  const ChatConversationView({
    super.key,
    required this.sessionId,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.s16,
      vertical: AppSpacing.s12,
    ),
    this.invocationIntent,
    this.onReplyChip,
    this.emptyBuilder,
    this.loadingBuilder,
    this.suggestCannedReplies = true,
  });

  final String sessionId;

  /// Inset around the message list. Sheets run tighter than the page.
  final EdgeInsets padding;

  /// Invocation intent that triggered this turn, forwarded to
  /// [MessageBubble] so the reply-chip suggester can specialise.
  final String? invocationIntent;

  /// When non-null, completed assistant turns render reply chips and
  /// call this with the tapped chip text.
  final void Function(String chip)? onReplyChip;

  /// Shown when the session has no messages yet. Defaults to an empty
  /// box so a host that wants nothing pays for nothing.
  final WidgetBuilder? emptyBuilder;

  /// Shown while the message stream is delivering its first snapshot.
  /// Defaults to a centered progress indicator; the full page passes an
  /// [AiChatSkeleton], the intent sheet a shimmer.
  final WidgetBuilder? loadingBuilder;

  /// Forwarded to [MessageBubble]. False on the conversation sheet so
  /// plain turns don't trail generic canned reply chips — only a menu the
  /// model actually wrote becomes a tappable choice list.
  final bool suggestCannedReplies;

  @override
  ConsumerState<ChatConversationView> createState() =>
      _ChatConversationViewState();
}

class _ChatConversationViewState extends ConsumerState<ChatConversationView> {
  final ScrollController _scroll = ScrollController();
  final Set<String> _renderedMessageIds = <String>{};
  bool _renderedInitialSnapshot = false;

  /// Whether the viewport is currently anchored at (or within
  /// [_bottomThreshold] of) the bottom of the list. We only follow new
  /// snapshots when this is true — once the user scrolls up to read
  /// history we stop pulling them back, and the floating jump-to-latest
  /// button below lets them re-anchor on demand.
  bool _atBottom = true;

  /// Pixels from the bottom that still count as "at the bottom". Wide
  /// enough that a momentum scroll-back near the edge doesn't detach.
  static const double _bottomThreshold = 96;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    final distance = pos.maxScrollExtent - pos.pixels;
    final next = distance <= _bottomThreshold;
    if (next != _atBottom) {
      setState(() => _atBottom = next);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(
          target,
          duration: Motion.fast,
          curve: Motion.standardDecelerate,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      chatMessagesStreamProvider(widget.sessionId),
    );

    // Follow new snapshots to the bottom — but only when the user is
    // still anchored there. Reading history without being yanked back
    // mid-scroll is the whole point of the at-bottom gate.
    ref.listen(chatMessagesStreamProvider(widget.sessionId), (_, next) {
      next.whenData((_) {
        if (_atBottom) _scrollToBottom();
      });
    });

    return messagesAsync.when(
      loading: () =>
          widget.loadingBuilder?.call(context) ??
          const Center(child: FCircularProgress()),
      error: (e, _) => Center(
        child: Text(AppLocalizations.of(context).commonLoadError(e.toString())),
      ),
      data: (messages) {
        if (messages.isEmpty) {
          _renderedInitialSnapshot = true;
          return widget.emptyBuilder?.call(context) ?? const SizedBox.shrink();
        }
        // Locate the trailing assistant and user messages once per
        // build — bubbles use these to gate the "regenerate" (assistant)
        // and "edit & resend" (user) affordances to the most recent
        // turn only. Editing mid-thread would silently overwrite all
        // follow-ups, which is almost never what users want.
        var lastAssistantIdx = -1;
        var lastUserIdx = -1;
        for (var i = messages.length - 1; i >= 0; i--) {
          if (lastAssistantIdx < 0 && messages[i].role == ChatRole.assistant) {
            lastAssistantIdx = i;
          }
          if (lastUserIdx < 0 && messages[i].role == ChatRole.user) {
            lastUserIdx = i;
          }
          if (lastAssistantIdx >= 0 && lastUserIdx >= 0) break;
        }
        final animateMessageIds = _renderedInitialSnapshot
            ? <String>{
                for (final message in messages)
                  if (!_renderedMessageIds.contains(message.id)) message.id,
              }
            : const <String>{};
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _renderedInitialSnapshot = true;
          _renderedMessageIds.addAll(messages.map((message) => message.id));
        });
        return Stack(
          children: [
            ListView.builder(
              controller: _scroll,
              padding: widget.padding,
              itemCount: messages.length,
              itemBuilder: (_, i) => MessageBubble(
                sessionId: widget.sessionId,
                message: messages[i],
                invocationIntent: widget.invocationIntent,
                onReplyChip: widget.onReplyChip,
                isLastAssistant: i == lastAssistantIdx,
                isLastUser: i == lastUserIdx,
                suggestCannedReplies: widget.suggestCannedReplies,
                animateIn: animateMessageIds.contains(messages[i].id),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: _JumpToBottomButton(
                visible: !_atBottom,
                onPressed: () => _scrollToBottom(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Floating "↓ jump to latest" button surfaced when the user has
/// scrolled away from the bottom of an active conversation. Fades /
/// scales in via [AnimatedSwitcher] so it doesn't pop in abruptly when
/// streaming starts.
class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.fast,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: !visible
          ? const SizedBox.shrink(key: ValueKey('jtb-empty'))
          : _JumpToBottomChip(
              key: const ValueKey('jtb-visible'),
              onPressed: onPressed,
            ),
    );
  }
}

class _JumpToBottomChip extends StatelessWidget {
  const _JumpToBottomChip({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return FTooltip(
      tipBuilder: (_, _) => Text(l10n.aiChatJumpToLatestTooltip),
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.background,
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).shadowColor.withValues(alpha: AppOpacity.light),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            FLucideIcons.arrowDown,
            size: AppIconSizes.h18,
            color: colors.foreground,
          ),
        ),
      ),
    );
  }
}
