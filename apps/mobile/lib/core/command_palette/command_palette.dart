/// Public API for the global command palette.
///
/// Wire `showCommandPalette` to the `Cmd/Ctrl+K` shortcut callback exposed
/// by `GlobalShortcutsScope`.
library;

export 'command_palette_dialog.dart' show showCommandPalette;
export 'command_palette_entry.dart';
export 'default_commands.dart';
