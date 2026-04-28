import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'shortcut_intents.dart';

/// One row in the shortcut help dialog. Pairs an [activator] with the [intent]
/// the global `Actions` widget will dispatch and a localization-key-style
/// [descriptionKey] so the help UI can look up a translated label.
@immutable
class ShortcutBinding {
  const ShortcutBinding({
    required this.activator,
    required this.intent,
    required this.descriptionKey,
  });

  final ShortcutActivator activator;
  final Intent intent;
  final String descriptionKey;
}

/// Built-in primary navigation tab count.
///
/// Kept here (not imported from the router) so `core/shortcuts/` stays free of
/// feature-layer dependencies — the [SwitchPrimaryTabIntent] handler is wired
/// up by `app/`, which knows about routes.
const int kPrimaryTabCount = 4;

/// Returns the global shortcut bindings, including both the macOS (`meta`) and
/// non-macOS (`control`) variant for `Cmd/Ctrl+...` combos so the same map
/// works on every desktop OS without runtime branching.
List<ShortcutBinding> globalShortcutBindings() {
  return <ShortcutBinding>[
    const ShortcutBinding(
      activator: SingleActivator(LogicalKeyboardKey.keyK, meta: true),
      intent: OpenCommandPaletteIntent(),
      descriptionKey: 'shortcutCommandPalette',
    ),
    const ShortcutBinding(
      activator: SingleActivator(LogicalKeyboardKey.keyK, control: true),
      intent: OpenCommandPaletteIntent(),
      descriptionKey: 'shortcutCommandPalette',
    ),
    const ShortcutBinding(
      activator: SingleActivator(LogicalKeyboardKey.slash, meta: true),
      intent: ShowShortcutHelpIntent(),
      descriptionKey: 'shortcutShowHelp',
    ),
    const ShortcutBinding(
      activator: SingleActivator(LogicalKeyboardKey.slash, control: true),
      intent: ShowShortcutHelpIntent(),
      descriptionKey: 'shortcutShowHelp',
    ),
    const ShortcutBinding(
      activator: SingleActivator(LogicalKeyboardKey.escape),
      intent: DismissOverlayIntent(),
      descriptionKey: 'shortcutDismissOverlay',
    ),
    for (int i = 0; i < kPrimaryTabCount; i++)
      ShortcutBinding(
        activator: SingleActivator(_digitForIndex(i)),
        intent: SwitchPrimaryTabIntent(i),
        descriptionKey: 'shortcutSwitchTab$i',
      ),
  ];
}

/// Build the activator → intent map consumed by [Shortcuts].
Map<ShortcutActivator, Intent> globalShortcutMap() {
  return <ShortcutActivator, Intent>{
    for (final ShortcutBinding b in globalShortcutBindings())
      b.activator: b.intent,
  };
}

LogicalKeyboardKey _digitForIndex(int index) {
  switch (index) {
    case 0:
      return LogicalKeyboardKey.digit1;
    case 1:
      return LogicalKeyboardKey.digit2;
    case 2:
      return LogicalKeyboardKey.digit3;
    case 3:
      return LogicalKeyboardKey.digit4;
    default:
      throw ArgumentError.value(index, 'index', 'unexpected primary tab index');
  }
}
