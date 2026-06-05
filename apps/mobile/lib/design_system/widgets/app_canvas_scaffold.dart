import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Headerless app canvas for root pages or master-detail shells that own their
/// own in-content chrome.
///
/// Prefer [AppPageScaffold], [AppFormPageScaffold], [ObjectDetailScaffold], or
/// [DomainTabScaffold] when a page has standard navigation chrome. This widget
/// documents the remaining intentional no-header cases without leaking raw
/// `FScaffold` usage into feature code.
class AppCanvasScaffold extends StatelessWidget {
  const AppCanvasScaffold({
    super.key,
    required this.child,
    this.childPad = false,
    this.transparentMaterial = true,
    this.resizeToAvoidBottomInset,
  });

  final Widget child;
  final bool childPad;
  final bool transparentMaterial;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final body = transparentMaterial
        ? Material(color: Colors.transparent, child: child)
        : child;
    return FScaffold(
      childPad: childPad,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset ?? true,
      child: body,
    );
  }
}
