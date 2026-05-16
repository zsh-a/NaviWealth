import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
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
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.invocationIntent,
    this.onReplyChip,
    this.emptyBuilder,
    this.loadingBuilder,
  });

  final String sessionId;

  /// Inset around the message list. Sheets run tighter than the page.
  final EdgeInsets padding;

  /// Wave 33 invocation intent that triggered this turn, forwarded to
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

  @override
  ConsumerState<ChatConversationView> createState() =>
      _ChatConversationViewState();
}

class _ChatConversationViewState extends ConsumerState<ChatConversationView> {
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

    // Follow every new snapshot to the bottom.
    ref.listen(chatMessagesStreamProvider(widget.sessionId), (_, next) {
      next.whenData((_) => _scrollToBottom());
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
          return widget.emptyBuilder?.call(context) ?? const SizedBox.shrink();
        }
        return ListView.builder(
          controller: _scroll,
          padding: widget.padding,
          itemCount: messages.length,
          itemBuilder: (_, i) => MessageBubble(
            sessionId: widget.sessionId,
            message: messages[i],
            invocationIntent: widget.invocationIntent,
            onReplyChip: widget.onReplyChip,
          ),
        );
      },
    );
  }
}
