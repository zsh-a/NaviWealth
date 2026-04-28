/// Public API for the keyboard-shortcut subsystem.
///
/// Wire `GlobalShortcutsScope` around `MaterialApp.router` to install the
/// global bindings (`Cmd/Ctrl+K`, `Cmd/Ctrl+/`, `Esc`, `1`-`4`). Drop a
/// `ShortcutScope` inside a feature subtree for page-local bindings.
library;

export 'global_shortcuts_scope.dart';
export 'keyboard_platform.dart' show areKeyboardShortcutsAvailable;
export 'shortcut_bindings.dart';
export 'shortcut_help_dialog.dart' show showShortcutHelpDialog;
export 'shortcut_intents.dart';
export 'shortcut_scope.dart';
