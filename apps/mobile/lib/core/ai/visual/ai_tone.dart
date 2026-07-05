/// Color discipline for AI surfaces.
///
/// AI surfaces use **four** color roles. Material's `tertiary` /
/// `secondary` are forbidden inside `lib/features/ai_chat/`,
/// `lib/features/settings/ui/ai/ai_*`, and `lib/core/ai/*`: when a new
/// status needs visual distinction, encode it with **iconography** or
/// **typography weight**, not a new hue.
///
/// Why so strict? The `tertiary` tone was overloaded across stale
/// markers, disclosures, and the undo banner — same hue, three
/// meanings. Calm Intelligence (§5.6) requires one alive color, one
/// alert color, and otherwise typography.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class AiTone {
  AiTone._();

  /// Default text on AI surfaces. Used for primary content.
  static Color onSurface(BuildContext c) => c.theme.colors.foreground;

  /// Secondary / metadata text. Most "label", "subtitle", "muted"
  /// strings live here. Replaces ad-hoc `onSurfaceVariant` lookups so
  /// future palette swaps land in one place.
  static Color muted(BuildContext c) => c.theme.colors.mutedForeground;

  /// The **only** active / accent color allowed on AI surfaces.
  /// Reserved for "AI is alive" signals (streaming cursor, selected
  /// filter, active capsule). Don't use as a decoration tone.
  static Color active(BuildContext c) => c.theme.colors.primary;

  /// Failure / denied / policy violation. Use sparingly — most "warn"
  /// or "stale" signals should encode in iconography, not color.
  static Color error(BuildContext c) => c.theme.colors.destructive;

  /// Hairline / divider tone. Stays subtle.
  static Color outline(BuildContext c) => c.theme.colors.border;

  /// Surface used for AI pill / capsule backgrounds. Sits 4% above
  /// the page surface, no shadow.
  static Color surfaceTint(BuildContext c) => c.theme.colors.secondary;
}
