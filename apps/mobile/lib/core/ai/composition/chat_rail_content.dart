/// `core/ai/composition/` — cross-domain shell for AI chat composition.
///
/// Domains that want to surface action / insight cards inside the AI
/// chat rail register [ChatRailContent] through the composition bundle.
/// The chat UI in `features/ai_chat/` reads only from the domain-neutral
/// provider so it stays unaware of which domains exist.
///
/// The data model is intentionally minimal — title + detail + icon +
/// route or typed AI invocation + tint. Domains keep their own richer
/// model and project down at composition time.
library;

import 'package:flutter/widgets.dart';

import '../intent/ai_intent_invocation.dart';

/// Semantic tone for a chat-rail icon. Resolved to a concrete [Color]
/// by the view layer via `context.appTheme.status`. Keeps composition
/// providers free of theme dependencies.
enum ChatRailTone { success, warning, danger, info }

class ChatRailContent {
  const ChatRailContent({
    required this.id,
    required this.headline,
    required this.detail,
    required this.icon,
    this.tone,
    this.route,
    this.intent,
    this.object,
    this.objectLabel,
    this.attrs = const <String, Object?>{},
    this.source,
  });

  /// Stable id used as a list key and (later) for trace attribution.
  /// Domains should namespace this — e.g. `'finance:fire_progress'`,
  /// `'health:hrv_drop'` — so the rail order survives future ranking.
  final String id;

  /// Short title shown next to the icon (one line, ellipsised).
  final String headline;

  /// Body copy shown under the headline (up to four lines).
  final String detail;

  /// Lucide / Forui icon rendered in the leading tile.
  final IconData icon;

  /// Optional semantic tone for the icon's background chip. When null
  /// the rail falls back to the theme primary.
  final ChatRailTone? tone;

  /// `go_router` path to deep-link to when the card is tapped. Null
  /// falls back to [intent] invocation when present.
  final String? route;

  /// Optional AI intent invoked when [route] is null. This keeps chat-rail
  /// actions object-semantic without requiring feature code to import the
  /// concrete chat sheet.
  final String? intent;

  /// Optional business object attached to [intent].
  final AiObjectRef? object;

  /// Human-readable object label shown by the AI invocation surface.
  final String? objectLabel;

  /// Additional context attributes attached to [intent].
  final Map<String, Object?> attrs;

  /// Invocation source tag. When null, `askAi()` uses the ambient route path.
  final String? source;
}
