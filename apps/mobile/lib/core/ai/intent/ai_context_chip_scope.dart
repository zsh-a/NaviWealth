/// §5.10 Layer 2 — declarative context plumbing for AI capsules.
///
/// Each view (chart card, table, detail page, …) advertises its
/// current "what is the user looking at right now" as an immutable
/// list of [AiContextChip]s wrapped in an [AiContextChipScope]. When
/// a descendant capsule fires (`AiObjectCapsule`, command palette
/// "ask AI", etc.) it reads the merged chip set via
/// [AiContextChipScope.chipsOf] and attaches it to the
/// [AiIntentInvocation] context.
///
/// Why an InheritedWidget instead of a Riverpod provider:
///
///   * The context is **per subtree**, not global. Two charts visible
///     at the same time both want to advertise their own timeframe;
///     the global `aiRouteContextProvider` would race.
///   * Lookups happen at the moment the capsule fires — not on every
///     scope rebuild. InheritedWidget gives O(depth) ancestor walk
///     without any state-management ceremony.
///   * Tests can wrap a widget in a `AiContextChipScope` literal
///     without spinning up a `ProviderContainer`.
///
/// The expected composition pattern is **nested scopes**: an outer
/// scope ("Activity tab, base currency CNY") wraps an inner one
/// ("12-month trend chart"). Innermost values win on duplicate
/// [AiContextChip.key]; older keys shine through unchanged.
library;

import 'package:flutter/widgets.dart';

/// One context fact the surrounding view wants the AI surface to know
/// when it fires. The [key] is what disambiguates duplicates from
/// nested scopes; [label] is what the chip renders (e.g. on the
/// command-palette result pane); [value] is the machine-readable
/// payload included in the AI invocation context map.
@immutable
class AiContextChip {
  const AiContextChip({
    required this.key,
    required this.label,
    required this.value,
  });

  /// Stable identifier used to deduplicate when an inner scope wants
  /// to override a chip from an ancestor. Examples: `'route'`,
  /// `'timeframe'`, `'currency'`, `'selection'`.
  final String key;

  /// Short, human-friendly summary — what the UI shows next to the
  /// AI capsule or in the command-palette result pane.
  final String label;

  /// Machine payload merged into [AiIntentInvocation.context] under
  /// [key]. Strings, numbers, lists, and maps round-trip cleanly into
  /// the intent's prompt-template substitution.
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is AiContextChip &&
      other.key == key &&
      other.label == label &&
      other.value == value;

  @override
  int get hashCode => Object.hash(key, label, value);
}

class AiContextChipScope extends InheritedWidget {
  const AiContextChipScope({
    super.key,
    required this.chips,
    required super.child,
  });

  /// Chips this scope contributes locally. Composes with ancestor
  /// scopes — see [chipsOf]. Deliberately a `List`, not a `Set`, so
  /// callers can preserve a meaningful render order.
  final List<AiContextChip> chips;

  /// Returns the merged chip set visible at [context] — outermost
  /// scope first, innermost overrides on duplicate [AiContextChip.key].
  ///
  /// Returns an empty list when the widget tree contains no
  /// [AiContextChipScope] above [context]. Safe to call from anywhere
  /// in a widget; does **not** establish an InheritedWidget dependency
  /// (the result is a snapshot for the moment of the lookup).
  static List<AiContextChip> chipsOf(BuildContext context) {
    final scopes = <AiContextChipScope>[];
    context.visitAncestorElements((Element ancestor) {
      final widget = ancestor.widget;
      if (widget is AiContextChipScope) scopes.add(widget);
      return true;
    });
    if (scopes.isEmpty) return const <AiContextChip>[];
    // `visitAncestorElements` walks innermost → outermost. Reverse so
    // we process outermost first and innermost overrides on
    // duplicate keys.
    final ordered = scopes.reversed;
    final byKey = <String, AiContextChip>{};
    final order = <String>[];
    for (final scope in ordered) {
      for (final chip in scope.chips) {
        if (!byKey.containsKey(chip.key)) order.add(chip.key);
        byKey[chip.key] = chip;
      }
    }
    return <AiContextChip>[for (final k in order) byKey[k]!];
  }

  /// Convenience: chip set as a `Map<key, value>` ready for inclusion
  /// in [AiIntentInvocation.context].
  static Map<String, Object?> contextMapOf(BuildContext context) {
    final chips = chipsOf(context);
    if (chips.isEmpty) return const <String, Object?>{};
    return <String, Object?>{for (final c in chips) c.key: c.value};
  }

  @override
  bool updateShouldNotify(covariant AiContextChipScope old) {
    if (chips.length != old.chips.length) return true;
    for (var i = 0; i < chips.length; i++) {
      if (chips[i] != old.chips[i]) return true;
    }
    return false;
  }
}
