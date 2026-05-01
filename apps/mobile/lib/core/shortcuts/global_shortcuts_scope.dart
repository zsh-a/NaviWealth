import 'package:flutter/widgets.dart';

import 'keyboard_platform.dart';
import 'shortcut_bindings.dart';
import 'shortcut_help_dialog.dart';
import 'shortcut_intents.dart';

/// Wraps the app with `Shortcuts` + `Actions` so the bindings declared in
/// [globalShortcutMap] dispatch to the callbacks supplied here.
///
/// On platforms where [areKeyboardShortcutsAvailable] is `false` (iOS /
/// Android native), this widget is a transparent passthrough — no listener,
/// no overhead, no chance of a Bluetooth keyboard hijacking the shell.
class GlobalShortcutsScope extends StatelessWidget {
  const GlobalShortcutsScope({
    required this.onSwitchPrimaryTab,
    required this.onOpenCommandPalette,
    required this.child,
    super.key,
  });

  /// Called when the user requests the n-th primary tab (`1`-`4`).
  /// `index` is 0-based.
  final void Function(int index) onSwitchPrimaryTab;

  /// Called when the user invokes the global command palette (`Cmd/Ctrl+K`).
  /// The supplied [BuildContext] is a descendant of the navigator and is
  /// suitable for `showDialog` / `GoRouter` calls.
  final void Function(BuildContext context) onOpenCommandPalette;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!areKeyboardShortcutsAvailable) {
      return child;
    }
    return Shortcuts(
      shortcuts: globalShortcutMap(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenCommandPaletteIntent:
              _GuardedContextAction<OpenCommandPaletteIntent>(
                onInvoke: (Intent _, BuildContext? ctx) {
                  if (ctx != null) {
                    onOpenCommandPalette(ctx);
                  }
                },
              ),
          ShowShortcutHelpIntent: _GuardedContextAction<ShowShortcutHelpIntent>(
            onInvoke: (Intent _, BuildContext? ctx) {
              if (ctx != null) {
                showShortcutHelpDialog(ctx);
              }
            },
          ),
          DismissOverlayIntent: _DismissOverlayAction(),
          SwitchPrimaryTabIntent: _GuardedAction<SwitchPrimaryTabIntent>(
            onInvoke: (Intent intent) {
              final SwitchPrimaryTabIntent i = intent as SwitchPrimaryTabIntent;
              if (i.index < 0 || i.index >= kPrimaryTabCount) return;
              onSwitchPrimaryTab(i.index);
            },
          ),
        },
        child: child,
      ),
    );
  }
}

/// Action that suppresses itself while a text input owns focus, so number
/// keys / `Cmd+K` typed into a field never trigger app navigation.
class _GuardedAction<T extends Intent> extends Action<T> {
  _GuardedAction({required this.onInvoke});

  final void Function(Intent intent) onInvoke;

  @override
  bool isEnabled(T intent) => !isTextInputFocused();

  @override
  bool consumesKey(T intent) => !isTextInputFocused();

  @override
  Object? invoke(T intent) {
    onInvoke(intent);
    return null;
  }
}

class _GuardedContextAction<T extends Intent> extends ContextAction<T> {
  _GuardedContextAction({required this.onInvoke});

  final void Function(Intent intent, BuildContext? context) onInvoke;

  @override
  bool isEnabled(T intent, [BuildContext? context]) => !isTextInputFocused();

  @override
  bool consumesKey(T intent) => !isTextInputFocused();

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    onInvoke(intent, context);
    return null;
  }
}

/// Esc handling intentionally bypasses the text-input guard: hitting `Esc`
/// inside a focused field should still close the surrounding dialog (after
/// which the OS will hand focus back to whatever was beneath it).
class _DismissOverlayAction extends ContextAction<DismissOverlayIntent> {
  @override
  bool isEnabled(DismissOverlayIntent intent, [BuildContext? context]) {
    if (context == null) return false;
    final NavigatorState? nav = Navigator.maybeOf(context, rootNavigator: true);
    return nav != null && nav.canPop();
  }

  @override
  Object? invoke(DismissOverlayIntent intent, [BuildContext? context]) {
    if (context == null) return null;
    Navigator.of(context, rootNavigator: true).maybePop();
    return null;
  }
}
