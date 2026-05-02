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

/// Collapse / expand the desktop sidebar. Bound to `Cmd/Ctrl+B`.
///
/// The handler talks to [SidebarCollapsedController] so the chevron in
/// the sidebar UI and the keyboard path stay in sync. On non-desktop
/// builds the action still fires but has no visible effect — the shell
/// only mounts the sidebar when the viewport is wide enough.
class ToggleSidebarIntent extends Intent {
  const ToggleSidebarIntent();
}
