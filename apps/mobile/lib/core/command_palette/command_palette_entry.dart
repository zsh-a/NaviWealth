import 'package:flutter/widgets.dart';

/// One row in the command palette list.
///
/// [run] is invoked with the navigator-rooted context after the palette has
/// closed, so commands that push routes (`context.go(...)`) work without
/// fighting the still-open dialog.
@immutable
class CommandPaletteEntry {
  const CommandPaletteEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.run,
    this.subtitle,
    this.keywords = const <String>[],
  });

  /// Stable identifier — used by tests and future telemetry. Not user-visible.
  final String id;

  /// Primary user-visible label.
  final String label;

  /// Optional secondary label shown in muted text below [label].
  final String? subtitle;

  final IconData icon;

  /// Extra strings the search query can match against (e.g. translations,
  /// synonyms, route paths). [label] is always searched too — no need to
  /// repeat it here.
  final List<String> keywords;

  final void Function(BuildContext context) run;

  /// True when [query] (already normalised) matches [label] or any keyword.
  bool matches(String query) {
    if (query.isEmpty) return true;
    if (label.toLowerCase().contains(query)) return true;
    for (final String k in keywords) {
      if (k.toLowerCase().contains(query)) return true;
    }
    return false;
  }
}
