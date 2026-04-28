import 'package:flutter/widgets.dart';

/// Open the global command palette. Bound to `Cmd/Ctrl+K`.
///
/// The palette UI itself ships with a later task — for now the action wires a
/// logger breadcrumb so we can verify the binding fires end-to-end.
class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

/// Show the keyboard shortcut help overlay. Bound to `Cmd/Ctrl+/`.
class ShowShortcutHelpIntent extends Intent {
  const ShowShortcutHelpIntent();
}

/// Dismiss the topmost dialog / popup / route. Bound to `Esc`.
class DismissOverlayIntent extends Intent {
  const DismissOverlayIntent();
}

/// Switch the root shell to the primary tab at [index] (0-based).
/// Bound to digit keys `1`-`4`.
class SwitchPrimaryTabIntent extends Intent {
  const SwitchPrimaryTabIntent(this.index);

  final int index;
}
