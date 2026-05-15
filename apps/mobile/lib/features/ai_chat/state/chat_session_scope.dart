import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

/// Resolves the *default* chat session id for [ownerUserId]: the most
/// recent existing thread, or a freshly created empty one.
///
/// Replaces the three near-identical imperative bootstraps that used to
/// live in `_AiChatPageState._ensureSession`,
/// `_AiChatSheetBodyState._ensureSession` and the happy path of
/// `_AiBottomSheetShellState._kick`. Those each kicked session creation
/// from `build()` via `addPostFrameCallback` guarded by a cluster of
/// mutable flags. As a `FutureProvider` the resolution is declarative,
/// deduplicated, cached for the surface's lifetime, and unit-testable
/// without pumping a widget.
///
/// `listSessions` (one-shot) — not the sessions *stream* — is used
/// deliberately: a `StreamProvider.future` may not deliver its first
/// emission until the next change notification fires, which is what
/// historically left the page stuck on "Preparing conversation…" until
/// the user manually tapped "+".
///
/// `autoDispose` + `family` keyed by user: the resolution caches while a
/// surface is mounted and re-resolves (picking the now-existing thread)
/// when the surface is reopened. The bottom-sheet's *always-new* session
/// path (fresh thread per `AiIntentInvocation`, titled from the intent,
/// prompt fired immediately) is intentionally NOT routed through here —
/// it is a different concern from "resume the user's conversation".
final defaultChatSessionProvider = FutureProvider.autoDispose
    .family<String, String>((ref, ownerUserId) async {
      final repo = await ref.watch(chatRepositoryProvider.future);
      final existing = await repo.listSessions(ownerUserId);
      if (existing.isNotEmpty) return existing.first.id;
      final created = await repo.createSession(ownerUserId: ownerUserId);
      return created.id;
    });
