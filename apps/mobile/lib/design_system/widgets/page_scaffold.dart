import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../tokens/breakpoints.dart';
import '../tokens/spacing_tokens.dart';

/// Unified page surface for non-master-detail feature pages.
///
/// Centralizes three responsibilities that were previously open-coded by
/// every feature:
///
///  * **Width capping on desktop / web.** Single-pane content is centered
///    inside a [maxWidth] (default [Spacing.contentMaxWidth] = 1200dp) so
///    cards and text columns stay readable on 1440 / 4K / ultrawide
///    monitors instead of stretching the full window. See
///    `apps/mobile/docs/design/01-responsive-layout.md` §6.
///  * **Breakpoint-aware horizontal padding.** Mobile width uses
///    [Spacing.pageMobile]; tablet/desktop widths use [Spacing.pageWide].
///  * **Optional aside slot.** Pages with secondary navigation, filters,
///    or summary side panels can pass an [aside]; it appears on the left
///    of the body at desktop widths and collapses into the body's
///    natural flow at narrower widths.
///
/// Master-detail pages should keep using `MasterDetailLayout` directly —
/// they need to fill the window so the splitter has room to breathe.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.aside,
    this.asideWidth = Spacing.asideDefault,
    this.maxWidth = Spacing.contentMaxWidth,
    this.padding,
    this.background,
    this.scrollableBody = false,
  });

  /// Main page content. When [scrollableBody] is `false` (default), the
  /// caller is responsible for providing its own `ListView` /
  /// `SingleChildScrollView`. When `true`, [PageScaffold] wraps [body] in
  /// a [SingleChildScrollView] — useful for pages whose body is a static
  /// `Column` of cards.
  final Widget body;

  /// Optional [PreferredSizeWidget] (typically `GlassAppBar`).
  final PreferredSizeWidget? appBar;

  /// Optional sidebar rendered on the left at desktop widths.
  final Widget? aside;

  /// Logical-pixel width reserved for [aside] on desktop. Ignored when
  /// [aside] is null.
  final double asideWidth;

  /// Max width of the centered content region on desktop / web. Pass
  /// `double.infinity` to opt out of width capping (useful inside a
  /// detail pane that already controls its width).
  final double maxWidth;

  /// Override for the page edge padding. Defaults to [Spacing.pageMobile]
  /// at mobile widths and [Spacing.pageWide] otherwise.
  final EdgeInsetsGeometry? padding;

  /// Optional override of the [Scaffold] background colour.
  final Color? background;

  /// When `true`, wraps [body] in a [SingleChildScrollView]. See [body].
  final bool scrollableBody;

  @override
  Widget build(BuildContext context) {
    // Per-route GlassBackdropScope: the AppBar, body cards, and any
    // floating shell glass surfaces inside this Scaffold share a single
    // GPU framebuffer capture instead of each capturing the backdrop
    // independently. On Skia/web this is a cheap no-op.
    return lgw.GlassBackdropScope(
      child: Scaffold(
        backgroundColor: background,
        appBar: appBar,
        body: SafeArea(
          top: appBar == null,
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isMobile = Breakpoints.isMobile(width);
              final isDesktop = Breakpoints.isDesktop(width);

              // Default page padding bakes in clearance for the mobile
              // shell's floating glass bottom bar so the last scroll item
              // isn't masked. When callers pass their own [padding], we
              // trust it as-is — they may have a ListView inside that's
              // already managing its own clearance.
              final EdgeInsets resolvedPadding;
              if (padding != null) {
                resolvedPadding = padding!.resolve(Directionality.of(context));
              } else {
                final mq = MediaQuery.of(context);
                final extraBottom = isMobile
                    ? Spacing.floatingBarClearance + mq.viewPadding.bottom
                    : mq.viewPadding.bottom;
                final base = isMobile ? Spacing.pageMobile : Spacing.pageWide;
                resolvedPadding = base.copyWith(
                  bottom: base.bottom + extraBottom,
                );
              }

              final hasAside = aside != null && isDesktop;
              final Widget content;
              if (hasAside) {
                content = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: asideWidth, child: aside),
                    const SizedBox(width: Spacing.s24),
                    Expanded(child: _wrapBody()),
                  ],
                );
              } else {
                content = _wrapBody();
              }

              final bool capped = !isMobile && maxWidth.isFinite;
              // Available width for content after horizontal page padding.
              final available =
                  width - resolvedPadding.left - resolvedPadding.right;
              final cap = hasAside
                  ? maxWidth + asideWidth + Spacing.s24
                  : maxWidth;
              final targetWidth = capped
                  ? math.min(available, cap)
                  : available;
              return Padding(
                padding: resolvedPadding,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: targetWidth, child: content),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _wrapBody() => scrollableBody
      ? SingleChildScrollView(child: body)
      : body;
}
