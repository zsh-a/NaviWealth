import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'back_header_action.dart';

/// Canonical scaffold for titled, pushed app pages that are not object details.
///
/// Top-level domain tabs use `ShellTabScaffold`; object detail pages use
/// `ObjectDetailScaffold`. This wrapper covers the common middle ground:
/// Analytics, FIRE, Cashflow, Rebalance and settings sub-pages that need the
/// standard back header plus optional trailing actions.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.child,
    this.actions = const <Widget>[],
    this.childPad = false,
    this.showBack = true,
    this.confirmLeave,
    this.transparentMaterial = true,
    this.resizeToAvoidBottomInset,
  }) : assert(title != null || titleWidget != null);

  final String? title;
  final Widget? titleWidget;
  final Widget child;
  final List<Widget> actions;
  final bool childPad;
  final bool showBack;
  final Future<bool> Function()? confirmLeave;
  final bool transparentMaterial;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final body = transparentMaterial
        ? Material(color: Colors.transparent, child: child)
        : child;
    return FScaffold(
      header: showBack
          ? appSubPageHeader(
              context: context,
              title: titleWidget ?? Text(title!),
              suffixes: actions,
              confirmLeave: confirmLeave,
            )
          : FHeader.nested(
              title: titleWidget ?? Text(title!),
              suffixes: actions,
            ),
      childPad: childPad,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset ?? true,
      child: body,
    );
  }
}
