import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import 'keyboard_platform.dart';
import 'shortcut_bindings.dart';
import 'shortcut_help_dialog.dart';
import 'shortcut_intents.dart';

/// Wraps the app with `Shortcuts` + `Actions` so the bindings declared in
/// [globalShortcutMap] dispatch to the callbacks supplied here.
///
/// On platforms where [areKeyboardShortcutsAvailable] is `false` (iOS /
/// Android native), the **keyboard** layer (`Shortcuts` map + vim `g`+key
/// handler) is skipped entirely — no listener, no chance of a Bluetooth
/// keyboard hijacking the shell. The `Actions` layer is still mounted with
/// the surface-invokable intents ([OpenCommandPaletteIntent],
/// [OpenAiChatIntent]) so a touch UI element (the mobile command-bar pill —
/// §5.10.2 / S2.5) can `Actions.maybeInvoke(context, OpenCommandPaletteIntent())`
/// without depending on a physical keyboard.
class GlobalShortcutsScope extends StatefulWidget {
  const GlobalShortcutsScope({
    required this.onSwitchPrimaryTab,
    required this.onOpenCommandPalette,
    required this.onToggleSidebar,
    required this.onOpenAiChat,
    required this.onVimGoto,
    required this.child,
    super.key,
  });

  /// Called when the user requests the n-th primary tab (`1`-`6`).
  /// `index` is 0-based.
  final void Function(int index) onSwitchPrimaryTab;

  /// Called when the user invokes the global command palette (`Cmd/Ctrl+K`).
  /// The supplied [BuildContext] is a descendant of the navigator and is
  /// suitable for `showDialog` / `GoRouter` calls.
  final void Function(BuildContext context) onOpenCommandPalette;

  /// Called when the user invokes the sidebar toggle (`Cmd/Ctrl+B`).
  final VoidCallback onToggleSidebar;

  /// Called when the user opens the AI chat sheet (`Cmd/Ctrl+/`).
  final void Function(BuildContext context) onOpenAiChat;

  /// Called when a vim-style `g`+key sequence completes.
  final void Function(String target) onVimGoto;

  final Widget child;

  @override
  State<GlobalShortcutsScope> createState() => _GlobalShortcutsScopeState();
}

class _GlobalShortcutsScopeState extends State<GlobalShortcutsScope> {
  bool _gPending = false;
  Timer? _gTimer;

  static const _kVimTimeout = Duration(milliseconds: 150);

  void _onVimG(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.keyG) {
      _gPending = true;
      _gTimer?.cancel();
      _gTimer = Timer(_kVimTimeout, () {
        _gPending = false;
      });
    } else if (_gPending) {
      _gPending = false;
      _gTimer?.cancel();
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyH) {
        widget.onVimGoto('home');
      } else if (key == LogicalKeyboardKey.keyA) {
        widget.onVimGoto('activity');
      } else if (key == LogicalKeyboardKey.keyI) {
        widget.onVimGoto('ai');
      } else if (key == LogicalKeyboardKey.keyN) {
        widget.onVimGoto('accounts');
      } else if (key == LogicalKeyboardKey.keyS) {
        widget.onVimGoto('settings');
      }
    }
  }

  @override
  void dispose() {
    _gTimer?.cancel();
    super.dispose();
  }

  Map<Type, Action<Intent>> _actionMap() => <Type, Action<Intent>>{
    OpenCommandPaletteIntent: _GuardedContextAction<OpenCommandPaletteIntent>(
      onInvoke: (Intent _, BuildContext? ctx) {
        if (ctx != null) widget.onOpenCommandPalette(ctx);
      },
    ),
    ShowShortcutHelpIntent: _GuardedContextAction<ShowShortcutHelpIntent>(
      onInvoke: (Intent _, BuildContext? ctx) {
        if (ctx != null) showShortcutHelpDialog(ctx);
      },
    ),
    OpenAiChatIntent: _GuardedContextAction<OpenAiChatIntent>(
      onInvoke: (Intent _, BuildContext? ctx) {
        if (ctx != null) widget.onOpenAiChat(ctx);
      },
    ),
    DismissOverlayIntent: _DismissOverlayAction(),
    SwitchPrimaryTabIntent: _GuardedAction<SwitchPrimaryTabIntent>(
      onInvoke: (Intent intent) {
        final SwitchPrimaryTabIntent i = intent as SwitchPrimaryTabIntent;
        if (i.index < 0 || i.index >= kPrimaryTabCount) return;
        widget.onSwitchPrimaryTab(i.index);
      },
    ),
    ToggleSidebarIntent: _GuardedAction<ToggleSidebarIntent>(
      onInvoke: (_) => widget.onToggleSidebar(),
    ),
  };

  @override
  Widget build(BuildContext context) {
    // §5.10.2 / S2.5 — the command-palette + AI-chat intents are
    // surface-invokable (a mobile pill taps them), so the `Actions`
    // layer mounts on every platform. Only the keyboard layer
    // (`Shortcuts` map + vim handler) is gated behind a physical
    // keyboard.
    if (!areKeyboardShortcutsAvailable) {
      return Actions(actions: _actionMap(), child: widget.child);
    }
    return Shortcuts(
      shortcuts: globalShortcutMap(),
      child: Actions(
        actions: _actionMap(),
        child: _VimKeyHandler(onKey: _onVimG, child: widget.child),
      ),
    );
  }
}

/// Wraps [child] with a [Focus] node that forwards raw key events to [onKey]
/// for vim-style `g`+key sequence handling. The focus node does not request
/// focus itself and is skipped from traversal — it only receives events that
/// bubble up from the shortcut scope.
class _VimKeyHandler extends StatelessWidget {
  const _VimKeyHandler({required this.onKey, required this.child});

  final void Function(KeyEvent event) onKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (!isTextInputFocused()) {
          onKey(event);
        }
        return KeyEventResult.ignored;
      },
      child: child,
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
///
/// Precedence mirrors [smartPop] so Esc, the toolbar back arrow, system
/// back, and post-save `popOrGo` always agree on what "back" means:
///
///  1. **root `Navigator.pop()`** — closes a modal sheet / dialog if any
///     overlay is on top (the original behavior).
///  2. **clear `?selected=`** — desktop master-detail; unmounts the
///     detail pane without leaving the list page.
///  3. **`GoRouter.pop()`** — pages pushed inside a shell branch.
///
/// `isEnabled` is the union of the three so the Esc keystroke isn't
/// silently swallowed when only one path is available.
class _DismissOverlayAction extends ContextAction<DismissOverlayIntent> {
  @override
  bool isEnabled(DismissOverlayIntent intent, [BuildContext? context]) {
    if (context == null) return false;
    final NavigatorState? rootNav = Navigator.maybeOf(
      context,
      rootNavigator: true,
    );
    if (rootNav != null && rootNav.canPop()) return true;
    final router = GoRouter.maybeOf(context);
    if (router == null) return false;
    if (router.canPop()) return true;
    return hasSelectedDetail(context);
  }

  @override
  Object? invoke(DismissOverlayIntent intent, [BuildContext? context]) {
    if (context == null) return null;
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop();
      return null;
    }
    if (clearSelectedDetail(context)) return null;
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) router.pop();
    return null;
  }
}
