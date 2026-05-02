import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'keyboard_platform.dart';

/// Keyboard shortcut overlay for master-detail list panes.
///
/// Wraps the master pane to provide vim-style navigation:
/// - `/` → focus the search/filter field
/// - `j` → select the next item
/// - `k` → select the previous item
///
/// All shortcuts are guarded by [isTextInputFocused] so typing in a
/// search field or text input never triggers navigation.
///
/// On platforms where keyboard shortcuts are unavailable (mobile), this
/// widget is a transparent passthrough.
class MasterDetailShortcuts extends StatelessWidget {
  const MasterDetailShortcuts({
    required this.child,
    this.onSearchFocus,
    this.onSelectNext,
    this.onSelectPrevious,
    super.key,
  });

  final Widget child;

  /// Called when the user presses `/` — typically focuses a search field.
  final VoidCallback? onSearchFocus;

  /// Called when the user presses `j` — selects the next list item.
  final VoidCallback? onSelectNext;

  /// Called when the user presses `k` — selects the previous list item.
  final VoidCallback? onSelectPrevious;

  @override
  Widget build(BuildContext context) {
    if (!areKeyboardShortcutsAvailable) return child;
    final bindings = <ShortcutActivator, VoidCallback>{
      if (onSearchFocus != null)
        const SingleActivator(LogicalKeyboardKey.slash): () {
          if (!isTextInputFocused()) onSearchFocus!();
        },
      if (onSelectNext != null)
        const SingleActivator(LogicalKeyboardKey.keyJ): () {
          if (!isTextInputFocused()) onSelectNext!();
        },
      if (onSelectPrevious != null)
        const SingleActivator(LogicalKeyboardKey.keyK): () {
          if (!isTextInputFocused()) onSelectPrevious!();
        },
    };
    if (bindings.isEmpty) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreFocusable: true,
      child: CallbackShortcuts(bindings: bindings, child: child),
    );
  }
}
