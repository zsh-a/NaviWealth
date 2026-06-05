import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'back_header_action.dart';

/// Unified scaffold for a domain's **pushed object-detail page** (an
/// asset, a Decision, a Concept, …).
///
/// Generalises the KnowledgeOS object-detail pattern (commit 4ebdbbe3)
/// into the one shape every domain's detail page should share: a ForUI
/// `FScaffold` whose header is built by [appSubPageHeader], so the
/// standard back arrow is injected automatically and optional trailing
/// [actions] (edit / refresh / share) sit on the right.
///
/// Wiring detail pages through this widget guarantees the back arrow can
/// never be forgotten — KnowledgeOS's object-detail page previously
/// shipped a bare `FHeader.nested(title: …)` with no way back on web —
/// and keeps the raw `FHeader.nested(` call site out of `lib/features`
/// (the back-nav coverage guard greps for it there). Top-level tab pages
/// use [DomainTabScaffold] instead.
class ObjectDetailScaffold extends StatelessWidget {
  const ObjectDetailScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.child,
    this.actions = const <Widget>[],
    this.childPad = false,
    this.confirmLeave,
    this.transparentMaterial = true,
  }) : assert(title != null || titleWidget != null);

  /// Plain header title, e.g. `'概念'` or an object label.
  final String? title;

  /// Custom header title widget for pages that need hero transitions or
  /// richer title composition.
  final Widget? titleWidget;

  /// Page body — usually a `ListView` of cards owning its own padding.
  final Widget child;

  /// Trailing header actions (`FHeaderAction`s): edit, refresh, share…
  /// Rendered to the right of the title; the back arrow stays on the
  /// left automatically.
  final List<Widget> actions;

  /// Forwarded to [FScaffold.childPad]. Defaults to `false`.
  final bool childPad;

  /// Runs before the back pop on pages holding unsaved input; when it
  /// resolves `false` the back is cancelled. See `appSubPageHeader`.
  final Future<bool> Function()? confirmLeave;

  /// Wrap the body in a transparent Material so ForUI/Material descendants
  /// render consistently without every detail page repeating the same shell.
  final bool transparentMaterial;

  @override
  Widget build(BuildContext context) {
    final body = transparentMaterial
        ? Material(color: Colors.transparent, child: child)
        : child;
    return FScaffold(
      header: appSubPageHeader(
        context: context,
        title: titleWidget ?? Text(title!),
        suffixes: actions,
        confirmLeave: confirmLeave,
      ),
      childPad: childPad,
      child: body,
    );
  }
}
