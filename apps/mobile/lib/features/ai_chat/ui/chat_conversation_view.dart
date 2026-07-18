import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import 'decision_request.dart';
import 'messages/message_bubble.dart';

/// The conversation timeline — message list + follow-scroll + the
/// loading / error / empty states — shared by every AI chat surface
/// (full page, slide-up sheet, intent bottom sheet).
///
/// The host owns chrome around the timeline (headers, composer);
/// this widget owns only the scrollable conversation.
class ChatConversationView extends ConsumerStatefulWidget {
  const ChatConversationView({
    super.key,
    required this.sessionId,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.s16,
      vertical: AppSpacing.s12,
    ),
    this.onDecisionSelect,
    this.emptyBuilder,
    this.loadingBuilder,
  });

  final String sessionId;

  /// Inset around the message list. Sheets run tighter than the page.
  final EdgeInsets padding;

  final void Function(DecisionSelectionRequest selection)? onDecisionSelect;

  /// Shown when the session has no messages yet. Defaults to an empty
  /// box so a host that wants nothing pays for nothing.
  final WidgetBuilder? emptyBuilder;

  /// Shown while the message stream is delivering its first snapshot.
  /// Defaults to a centered progress indicator; the full page passes an
  /// [AiChatSkeleton], the intent sheet a shimmer.
  final WidgetBuilder? loadingBuilder;

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

  /// Messages arrived while the user was reading history.
  int _unseenCount = 0;
  int _lastMessageCount = 0;

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
      setState(() {
        _atBottom = next;
        if (next) _unseenCount = 0;
      });
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scroll.hasClients) return;
    setState(() => _unseenCount = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated &&
          AppMotionPolicy.isEnabled(context, role: AppMotionRole.transition)) {
        _scroll.animateTo(
          target,
          duration: AppMotionPolicy.duration(
            context,
            Motion.fast,
            role: AppMotionRole.transition,
          ),
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
      next.whenData((messages) {
        final grew = messages.length > _lastMessageCount;
        _lastMessageCount = messages.length;
        if (_atBottom) {
          _scrollToBottom();
        } else if (grew) {
          setState(() => _unseenCount += 1);
        }
      });
    });

    return messagesAsync.when(
      loading: () =>
          widget.loadingBuilder?.call(context) ??
          const Center(child: FCircularProgress()),
      error: (e, _) => Center(child: Text(userSafeErrorMessage(context, e))),
      data: (messages) {
        if (messages.isEmpty) {
          _renderedInitialSnapshot = true;
          _lastMessageCount = 0;
          return widget.emptyBuilder?.call(context) ?? const SizedBox.shrink();
        }
        _lastMessageCount = messages.length;
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

        final items = _buildTimelineItems(messages);
        return Stack(
          children: [
            ListView.builder(
              controller: _scroll,
              padding: widget.padding,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return switch (item) {
                  _DateHeaderItem(:final label) => _DateSeparator(label: label),
                  _MessageItem(:final index) => MessageBubble(
                    sessionId: widget.sessionId,
                    message: messages[index],
                    onDecisionSelect: widget.onDecisionSelect,
                    isLastAssistant: index == lastAssistantIdx,
                    isLastUser: index == lastUserIdx,
                    animateIn: animateMessageIds.contains(messages[index].id),
                  ),
                };
              },
            ),
            Positioned(
              right: AppSpacing.s16,
              bottom: AppSpacing.s16,
              child: _JumpToBottomButton(
                visible: !_atBottom,
                unseenCount: _unseenCount,
                onPressed: () => _scrollToBottom(),
              ),
            ),
          ],
        );
      },
    );
  }

  List<_TimelineItem> _buildTimelineItems(List<ChatMessage> messages) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final items = <_TimelineItem>[];
    DateTime? lastDay;
    for (var i = 0; i < messages.length; i++) {
      final day = DateTime(
        messages[i].createdAt.toLocal().year,
        messages[i].createdAt.toLocal().month,
        messages[i].createdAt.toLocal().day,
      );
      if (lastDay == null || day != lastDay) {
        items.add(_DateHeaderItem(_dateLabel(l10n, day, now)));
        lastDay = day;
      }
      items.add(_MessageItem(i));
    }
    return items;
  }

  String _dateLabel(AppLocalizations l10n, DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return l10n.aiChatDateToday;
    if (day == yesterday) return l10n.aiChatDateYesterday;
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }
}

sealed class _TimelineItem {
  const _TimelineItem();
}

class _DateHeaderItem extends _TimelineItem {
  const _DateHeaderItem(this.label);
  final String label;
}

class _MessageItem extends _TimelineItem {
  const _MessageItem(this.index);
  final int index;
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: AppStroke.hairline,
              color: context.theme.colors.border.withValues(
                alpha: AppOpacity.scrim,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
            child: Text(
              label,
              style: context.microCaptionStyle.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: Container(
              height: AppStroke.hairline,
              color: context.theme.colors.border.withValues(
                alpha: AppOpacity.scrim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating "↓ jump to latest" button surfaced when the user has
/// scrolled away from the bottom of an active conversation. Fades /
/// scales in via [AnimatedSwitcher] so it doesn't pop in abruptly when
/// streaming starts.
class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({
    required this.visible,
    required this.unseenCount,
    required this.onPressed,
  });

  final bool visible;
  final int unseenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotionPolicy.duration(context, Motion.fast),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: !visible
          ? const SizedBox.shrink(key: ValueKey('jtb-empty'))
          : _JumpToBottomChip(
              key: const ValueKey('jtb-visible'),
              unseenCount: unseenCount,
              onPressed: onPressed,
            ),
    );
  }
}

class _JumpToBottomChip extends StatelessWidget {
  const _JumpToBottomChip({
    super.key,
    required this.unseenCount,
    required this.onPressed,
  });

  final int unseenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final label = unseenCount > 0
        ? l10n.aiChatJumpToLatestWithCount(unseenCount)
        : l10n.aiChatJumpToLatest;
    return FTooltip(
      tipBuilder: (_, _) => Text(l10n.aiChatJumpToLatestTooltip),
      child: FTappable(
        onPress: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            color: colors.background,
            border: Border.all(color: colors.border),
            boxShadow: AppShadow.elevation2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FLucideIcons.arrowDown,
                size: AppIconSizes.sm,
                color: colors.foreground,
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                label,
                style: context.captionLabelStyle.copyWith(
                  color: colors.foreground,
                ),
              ),
              if (unseenCount > 0) ...[
                const SizedBox(width: AppSpacing.s6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
