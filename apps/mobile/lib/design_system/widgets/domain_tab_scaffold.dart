import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Unified scaffold for a domain's **top-level tab / hub page** (Today,
/// Trend, Inbox, Library, …).
///
/// Every LifeOS domain renders its root surfaces the same way: a ForUI
/// `FScaffold` + a back-less `FHeader.nested` title + a body that owns
/// its own padding. Before this widget each domain hand-rolled that
/// trio — HealthOS even shipped a Material `Scaffold`/`AppBar`, reading
/// as a different app (the 2026-05-29 cross-domain interaction audit).
/// Routing tab pages through this scaffold makes the chrome identical by
/// construction and keeps the raw `FHeader.nested(` call site out of
/// `lib/features` (so the back-nav coverage guard doesn't need a
/// per-domain allowlist entry — tab roots have no back arrow by design).
///
/// Pushed detail pages use [ObjectDetailScaffold] instead — they DO get
/// a back arrow.
class DomainTabScaffold extends StatelessWidget {
  const DomainTabScaffold({
    super.key,
    required this.title,
    required this.child,
    this.childPad = false,
  });

  /// Plain header title, e.g. `'今日 · HealthOS'`.
  final String title;

  /// Page body. Owns its own scroll + padding (typically a `ListView`
  /// with `EdgeInsets.all(AppSpacing.s16)`), or a `Stack` when the page
  /// floats an action button.
  final Widget child;

  /// Forwarded to [FScaffold.childPad]. Defaults to `false` because tab
  /// bodies pad themselves; flip to `true` only for trivial centered
  /// content.
  final bool childPad;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader.nested(title: Text(title)),
      childPad: childPad,
      child: child,
    );
  }
}
