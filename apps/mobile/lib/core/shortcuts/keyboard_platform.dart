import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether keyboard shortcuts should be active on the current platform.
///
/// The wealth app's primary mobile experience is touch — shortcuts are
/// installed only on desktop browsers and native desktop builds. iOS / Android
/// (including Flutter Web running on a phone) skip the listener entirely so a
/// Bluetooth keyboard can't accidentally trigger app navigation.
bool get areKeyboardShortcutsAvailable {
  if (kIsWeb) {
    // On web we cannot easily distinguish a desktop browser from a tablet
    // browser without UA sniffing; the input-focus guard below keeps things
    // sane when a soft keyboard is active.
    return true;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// True while a text-input widget owns primary focus.
///
/// Used by global shortcut actions to bail out so typing into a `TextField`
/// never triggers app-level navigation (e.g. pressing `2` while editing the
/// asset name should NOT jump to the Assets tab).
bool isTextInputFocused() {
  final FocusNode? node = FocusManager.instance.primaryFocus;
  if (node == null || !node.hasPrimaryFocus) {
    return false;
  }
  final BuildContext? ctx = node.context;
  if (ctx == null) {
    return false;
  }
  if (ctx.widget is EditableText) {
    return true;
  }
  bool editing = false;
  ctx.visitAncestorElements((Element element) {
    if (element.widget is EditableText) {
      editing = true;
      return false;
    }
    return true;
  });
  return editing;
}
