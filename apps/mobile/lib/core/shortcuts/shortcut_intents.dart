import 'package:flutter/widgets.dart';

/// Open the global command palette. Bound to `Cmd/Ctrl+K`.
class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

/// Show the keyboard shortcut help overlay. Bound to `?`.
class ShowShortcutHelpIntent extends Intent {
  const ShowShortcutHelpIntent();
}

/// Open the AI chat sheet. Bound to `Cmd/Ctrl+/`.
class OpenAiChatIntent extends Intent {
  const OpenAiChatIntent();
}

/// Dismiss the topmost dialog / popup / route. Bound to `Esc`.
class DismissOverlayIntent extends Intent {
  const DismissOverlayIntent();
}

/// Switch the root shell to the primary tab at [index] (0-based).
/// Bound to digit keys `1`-`6`.
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

/// Navigate via vim-style `g` then a key. Fired after the second keypress
/// within the timeout window.
class VimGotoIntent extends Intent {
  const VimGotoIntent(this.target);

  final String target;
}

/// Focus the search/filter field in a master-detail list pane. Bound to `/`.
class ListSearchFocusIntent extends Intent {
  const ListSearchFocusIntent();
}

/// Select the next item in a master-detail list. Bound to `j`.
class ListSelectNextIntent extends Intent {
  const ListSelectNextIntent();
}

/// Select the previous item in a master-detail list. Bound to `k`.
class ListSelectPreviousIntent extends Intent {
  const ListSelectPreviousIntent();
}
