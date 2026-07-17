import 'package:flutter_riverpod/legacy.dart';

/// Pending text to drop into the composer for a session.
///
/// Used for:
///  - edit-and-resend: [replaceMessageId] set → next submit calls
///    [ChatController.editAndResend] instead of a fresh send;
///  - external prefills that arrive after the composer mounts.
class ComposerDraft {
  const ComposerDraft({required this.text, this.replaceMessageId});

  final String text;

  /// When non-null, the next composer submit replaces this user turn
  /// (and discards every follow-up) rather than appending a new one.
  final String? replaceMessageId;
}

/// Ephemeral per-session draft. Auto-disposed with the chat surface.
/// Writers set a value; [ChatComposer] consumes and clears it.
final chatComposerDraftProvider = StateProvider.autoDispose
    .family<ComposerDraft?, String>((ref, sessionId) => null);
