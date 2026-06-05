import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'back_header_action.dart';

/// Canonical page shell for full-screen pushed forms.
///
/// Pair with [AppFormScaffoldBody] for forms with a pinned action bar. This
/// wrapper owns the standard back header and disables scaffold-driven keyboard
/// resizing so the form body can handle IME avoidance consistently.
class AppFormPageScaffold extends StatelessWidget {
  const AppFormPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.confirmLeave,
    this.transparentMaterial = true,
  });

  final Widget title;
  final Widget child;
  final List<Widget> actions;
  final Future<bool> Function()? confirmLeave;
  final bool transparentMaterial;

  @override
  Widget build(BuildContext context) {
    final body = transparentMaterial
        ? Material(color: Colors.transparent, child: child)
        : child;
    return FScaffold(
      header: appSubPageHeader(
        context: context,
        title: title,
        suffixes: actions,
        confirmLeave: confirmLeave,
      ),
      childPad: false,
      resizeToAvoidBottomInset: false,
      child: body,
    );
  }
}
