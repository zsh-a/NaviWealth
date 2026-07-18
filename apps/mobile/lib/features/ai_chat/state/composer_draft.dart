import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';

/// Pending text to drop into the composer for a session.
///
/// Used for:
///  - edit-and-resend: [replaceMessageId] set → next submit calls
///    [ChatController.editAndResend] instead of a fresh send;
///  - external prefills that arrive after the composer mounts;
///  - restored drafts after process death (text only — no replace id).
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

const _kComposerDraftPrefix = 'ai_chat.composer_draft.';

/// Persist free-form composer text across app restarts. Edit-and-resend
/// drafts are intentionally *not* persisted (they need a live message id).
class ComposerDraftStore {
  ComposerDraftStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(String sessionId) => '$_kComposerDraftPrefix$sessionId';

  String? load(String sessionId) {
    final value = _prefs.getString(_key(sessionId));
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  Future<void> save(String sessionId, String text) async {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) {
      await clear(sessionId);
      return;
    }
    await _prefs.setString(_key(sessionId), trimmed);
  }

  Future<void> clear(String sessionId) async {
    await _prefs.remove(_key(sessionId));
  }
}

final composerDraftStoreProvider = Provider<ComposerDraftStore>((ref) {
  return ComposerDraftStore(ref.watch(sharedPreferencesProvider));
});
