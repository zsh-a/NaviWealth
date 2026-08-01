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

  final ValueNotifier<bool> _atBottom = ValueNotifier(true);
  final ValueNotifier<int> _unseenCount = ValueNotifier(0);

  int _lastMessageCount = 0;

  List<_TimelineItem>? _cachedItems;

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
    _atBottom.dispose();
    _unseenCount.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _cachedItems = null;
      _renderedMessageIds.clear();
      _renderedInitialSnapshot = false;
      _lastMessageCount = 0;
    }
  }

  List<_TimelineItem> _buildTimelineItems(List<ChatTimelineSlot> slots) {
    _cachedItems ??= () {
      final l10n = AppLocalizations.of(context);
      final now = DateTime.now();
      final items = <_TimelineItem>[];
      DateTime? lastDay;
      for (final slot in slots) {
        final day = DateTime(
          slot.createdAt.toLocal().year,
          slot.createdAt.toLocal().month,
          slot.createdAt.toLocal().day,
        );
        if (lastDay == null || day != lastDay) {
          items.add(_DateHeaderItem(_dateLabel(l10n, day, now)));
          lastDay = day;
        }
        items.add(_MessageItem(slot));
      }
      return items;
    }();
    return _cachedItems!;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    final distance = pos.maxScrollExtent - pos.pixels;
    final next = distance <= _bottomThreshold;
    if (next != _atBottom.value) {
      _atBottom.value = next;
      if (next) _unseenCount.value = 0;
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scroll.hasClients) return;
    _unseenCount.value = 0;
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
    final structureAsync = ref.watch(
      chatTimelineStructureProvider(widget.sessionId),
    );

    // Follow new snapshots to the bottom — but only when the user is
    // still anchored there. Structure changes (append/status) fire this;
    // pure token deltas do not, because the structure fingerprint omits
    // content. Token follow uses the at-bottom gate + listen on the full
    // stream without rebuilding the list host.
    ref.listen(chatMessagesStreamProvider(widget.sessionId), (_, next) {
      next.whenData((messages) {
        final grew = messages.length > _lastMessageCount;
        _lastMessageCount = messages.length;
        if (_atBottom.value) {
          _scrollToBottom();
        } else if (grew) {
          _unseenCount.value += 1;
        }
      });
    });

    return structureAsync.when(
      loading: () =>
          widget.loadingBuilder?.call(context) ??
          const Center(child: FCircularProgress()),
      error: (e, st) => kDefaultError(
        context,
        e,
        st,
        onRetry: () =>
            ref.invalidate(chatMessagesStreamProvider(widget.sessionId)),
      ),
      data: (slots) {
        if (slots.isEmpty) {
          _renderedInitialSnapshot = true;
          _lastMessageCount = 0;
          return widget.emptyBuilder?.call(context) ?? const SizedBox.shrink();
        }
        _lastMessageCount = slots.length;

        var lastAssistantId = '';
        var lastUserId = '';
        for (var i = slots.length - 1; i >= 0; i--) {
          if (lastAssistantId.isEmpty && slots[i].role == ChatRole.assistant) {
            lastAssistantId = slots[i].id;
          }
          if (lastUserId.isEmpty && slots[i].role == ChatRole.user) {
            lastUserId = slots[i].id;
          }
          if (lastAssistantId.isNotEmpty && lastUserId.isNotEmpty) break;
        }

        final animateMessageIds = _renderedInitialSnapshot
            ? <String>{
                for (final slot in slots)
                  if (!_renderedMessageIds.contains(slot.id)) slot.id,
              }
            : const <String>{};
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _renderedInitialSnapshot = true;
          _renderedMessageIds.addAll(slots.map((slot) => slot.id));
        });

        final items = _buildTimelineItems(slots);
        return Stack(
          children: [
            ListView.builder(
              controller: _scroll,
              padding: widget.padding,
              itemCount: items.length,
              addAutomaticKeepAlives: false,
              itemBuilder: (_, i) {
                final item = items[i];
                return switch (item) {
                  _DateHeaderItem(:final label) => _DateSeparator(label: label),
                  _MessageItem(:final slot) => RepaintBoundary(
                    child: _BoundMessageBubble(
                      key: ValueKey(slot.id),
                      sessionId: widget.sessionId,
                      messageId: slot.id,
                      onDecisionSelect: widget.onDecisionSelect,
                      isLastAssistant: slot.id == lastAssistantId,
                      isLastUser: slot.id == lastUserId,
                      animateIn:
                          animateMessageIds.contains(slot.id) &&
                              slot.id == slots.last.id,
                    ),
                  ),
                };
              },
            ),
            Positioned(
              right: AppSpacing.s16,
              bottom: AppSpacing.s16,
              child: _JumpToBottomOverlay(
                atBottom: _atBottom,
                unseenCount: _unseenCount,
                onPressed: () => _scrollToBottom(),
              ),
            ),
          ],
        );
      },
    );
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

/// Watches only its own message version so streaming tokens rebuild this
/// bubble and not every settled row in the list.
class _BoundMessageBubble extends ConsumerWidget {
  const _BoundMessageBubble({
    super.key,
    required this.sessionId,
    required this.messageId,
    required this.isLastAssistant,
    required this.isLastUser,
    required this.animateIn,
    this.onDecisionSelect,
  });

  final String sessionId;
  final String messageId;
  final bool isLastAssistant;
  final bool isLastUser;
  final bool animateIn;
  final void Function(DecisionSelectionRequest selection)? onDecisionSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(
      chatMessageByIdProvider((sessionId: sessionId, messageId: messageId)),
    );
    if (message == null) return const SizedBox.shrink();
    return MessageBubble(
      sessionId: sessionId,
      message: message,
      onDecisionSelect: onDecisionSelect,
      isLastAssistant: isLastAssistant,
      isLastUser: isLastUser,
      animateIn: animateIn,
    );
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
  const _MessageItem(this.slot);
  final ChatTimelineSlot slot;
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

/// Isolates jump-button rebuilds from the message list host.
class _JumpToBottomOverlay extends StatelessWidget {
  const _JumpToBottomOverlay({
    required this.atBottom,
    required this.unseenCount,
    required this.onPressed,
  });

  final ValueNotifier<bool> atBottom;
  final ValueNotifier<int> unseenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: atBottom,
      builder: (context, isAtBottom, _) {
        return ValueListenableBuilder<int>(
          valueListenable: unseenCount,
          builder: (context, count, _) {
            return _JumpToBottomButton(
              visible: !isAtBottom,
              unseenCount: count,
              onPressed: onPressed,
            );
          },
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
      child: AppTappable(
        onPress: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(AppRadius.full),
            boxShadow: AppShadow.elevation2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FLucideIcons.arrowDown,
                size: AppIconSizes.sm,
                color: colors.primaryForeground,
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                label,
                style: context.captionLabelStyle.copyWith(
                  color: colors.primaryForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
