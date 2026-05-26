/// `core/ai/composition/` — cross-domain shell for AI chat composition.
///
/// Phase D-1.6: every domain that wants to surface action / insight
/// cards inside the AI chat rail registers a [ChatRailContent] list via
/// a Riverpod provider override (see `chat_rail_provider.dart`). The
/// chat UI in `features/ai_chat/` reads only from that provider so it
/// stays unaware of which domains exist.
///
/// The data model is intentionally minimal — title + detail + icon +
/// route + tint. Domains keep their own richer model (e.g. Finance's
/// `InsightItem`) and project down at composition time.
library;

import 'package:flutter/widgets.dart';

class ChatRailContent {
  const ChatRailContent({
    required this.id,
    required this.headline,
    required this.detail,
    required this.icon,
    this.iconColor,
    this.route,
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

  /// Optional tint for the icon's background chip. When null the rail
  /// falls back to the theme primary.
  final Color? iconColor;

  /// `go_router` path to deep-link to when the card is tapped. Null
  /// disables tap.
  final String? route;
}
