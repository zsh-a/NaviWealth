import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/text_style_presets.dart';

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
///
/// ### Cross-domain shell chrome ([leading] / [actions])
///
/// This widget owns only *presentation*. The shell-level chrome —
/// the domain switcher chip and the global Search / Settings actions —
/// is composed one layer up (`core/shell/shell_chrome.dart`) and passed in via
/// [leading] (a header prefix) and [actions] (header suffixes). Keeping
/// the injection out of `design_system` preserves this layer as a leaf
/// (no `app/` or `core/shell` imports).
///
/// ### Scroll-collapse
///
/// To avoid permanently occupying vertical space, the header collapses
/// when the body scrolls down (reading) and reappears on scroll-up or at
/// the top of the list. The collapse is pure UI — a
/// [NotificationListener] over [UserScrollNotification] driving an
/// [AnimatedSize] — so it works whether the body is a `ListView`, a
/// sliver, or a nested scroll view.
class DomainTabScaffold extends StatefulWidget {
  const DomainTabScaffold({
    super.key,
    required this.title,
    required this.child,
    this.leading,
    this.actions = const <Widget>[],
    this.childPad = false,
    this.collapseOnScroll = true,
  });

  /// Plain header title, e.g. `'今日 · HealthOS'`.
  final String title;

  /// Page body. Owns its own scroll + padding (typically a `ListView`
  /// with `EdgeInsets.all(AppSpacing.s16)`), or a `Stack` when the page
  /// floats an action button.
  final Widget child;

  /// Optional header *prefix* (rendered left of the title). The shell
  /// passes the domain switcher chip here; tab roots have no back arrow
  /// so the prefix slot is free. `null` → no prefix.
  final Widget? leading;

  /// Trailing header actions (`FHeaderAction`s). Domain-owned actions
  /// (`+`, filter, …) come first; the shell appends the global Search /
  /// Settings actions when it composes the list.
  final List<Widget> actions;

  /// Forwarded to [FScaffold.childPad]. Defaults to `false` because tab
  /// bodies pad themselves; flip to `true` only for trivial centered
  /// content.
  final bool childPad;

  /// When `true` (default) the header hides on scroll-down and returns on
  /// scroll-up / at-top. Set `false` for pages whose body never scrolls
  /// (the header would never come back).
  final bool collapseOnScroll;

  @override
  State<DomainTabScaffold> createState() => _DomainTabScaffoldState();
}

class _DomainTabScaffoldState extends State<DomainTabScaffold> {
  bool _headerVisible = true;

  bool _onScroll(UserScrollNotification notification) {
    if (!widget.collapseOnScroll) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    // Content too short to scroll — keep the header pinned so it can't get
    // stuck collapsed on a page that never scrolls back up.
    if (notification.metrics.maxScrollExtent <= 0) {
      if (!_headerVisible) setState(() => _headerVisible = true);
      return false;
    }

    switch (notification.direction) {
      case ScrollDirection.reverse:
        if (_headerVisible) setState(() => _headerVisible = false);
      case ScrollDirection.forward:
        if (!_headerVisible) setState(() => _headerVisible = true);
      case ScrollDirection.idle:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final hasControls = widget.leading != null || widget.actions.isNotEmpty;
    final prefixes = widget.leading == null
        ? const <Widget>[]
        : <Widget>[widget.leading!];
    final header = AnimatedSize(
      duration: AppMotionPolicy.duration(context, Motion.medium),
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      child: _headerVisible
          ? FHeader.nested(
              prefixes: prefixes,
              title: _DomainHeaderTitle(widget.title),
              suffixes: widget.actions,
            )
          // Keep shell controls reachable while the title collapses away.
          // Pages with no controls still collapse to zero height.
          : hasControls
          ? _CompactHeaderControls(prefixes: prefixes, actions: widget.actions)
          : const SizedBox(width: double.infinity),
    );

    return NotificationListener<UserScrollNotification>(
      onNotification: _onScroll,
      child: FScaffold(
        header: header,
        childPad: widget.childPad,
        child: widget.child,
      ),
    );
  }
}

class _DomainHeaderTitle extends StatelessWidget {
  const _DomainHeaderTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // Editorial tab title — calm weight, not a shouting headline.
      style: context.displayTitleStyle.copyWith(
        color: colors.foreground,
        height: 1.1,
      ),
    );
  }
}

class _CompactHeaderControls extends StatelessWidget {
  const _CompactHeaderControls({required this.prefixes, required this.actions});

  final List<Widget> prefixes;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: AppSpacing.s56,
        child: FHeader.nested(
          prefixes: prefixes,
          title: const SizedBox.shrink(),
          suffixes: actions,
        ),
      ),
    );
  }
}
