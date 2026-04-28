import 'package:flutter/widgets.dart';

import 'keyboard_platform.dart';

/// Feature-local shortcut "hook".
///
/// Drop a [ShortcutScope] anywhere in a feature's widget subtree to register
/// shortcuts that should only fire while that subtree contains focus. The
/// scope is a transparent passthrough on platforms where keyboard shortcuts
/// are disabled (see [areKeyboardShortcutsAvailable]) and while a text input
/// owns primary focus.
///
/// Example:
/// ```dart
/// ShortcutScope(
///   shortcuts: {
///     const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _addAsset,
///     const SingleActivator(LogicalKeyboardKey.keyN, control: true): _addAsset,
///   },
///   child: AssetsListView(...),
/// )
/// ```
class ShortcutScope extends StatelessWidget {
  const ShortcutScope({
    required this.shortcuts,
    required this.child,
    this.autofocus = false,
    super.key,
  });

  final Map<ShortcutActivator, VoidCallback> shortcuts;
  final Widget child;

  /// When `true`, requests focus for the scope on first build so the bindings
  /// fire without the user having to click into the subtree first. Use
  /// sparingly — autofocus on every page fights with text inputs.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    if (!areKeyboardShortcutsAvailable || shortcuts.isEmpty) {
      return child;
    }
    return Focus(
      autofocus: autofocus,
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreFocusable: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          for (final MapEntry<ShortcutActivator, VoidCallback> e
              in shortcuts.entries)
            e.key: () {
              if (isTextInputFocused()) return;
              e.value();
            },
        },
        child: child,
      ),
    );
  }
}
