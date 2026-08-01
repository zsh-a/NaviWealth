import 'package:flutter/material.dart';

import '../tokens/dimens_tokens.dart';
import 'app_collapsing_stage.dart';
import 'app_refresh_indicator.dart';
import 'atmosphere.dart';
import 'staggered_column.dart';

/// Immersive "brief" page composition (Phase A).
///
/// Layout:
/// ```
/// [atmosphere]
///   greeting / identity
///   stage (hero metric + optional chart)
///   primary modules
///   secondary / timeline
/// ```
///
/// Prefer this over ad-hoc ListView stacks for domain Today surfaces and
/// the Life hub.
class BriefScaffold extends StatelessWidget {
  const BriefScaffold({
    super.key,
    required this.greeting,
    required this.stage,
    this.modules = const <Widget>[],
    this.secondary = const <Widget>[],
    this.padding,
    this.atmosphere = true,
    this.stagger = true,
    this.onRefresh,
    this.stickyBuilder,
    this.stickyPadding,
    this.maxContentWidth,
  });

  /// Top identity row (greeting + chrome).
  final Widget greeting;

  /// Single visual anchor (hero metric, scrub stage, recovery).
  final Widget stage;

  /// Primary modules under the stage.
  final List<Widget> modules;

  /// Secondary content (timeline, deeper cards).
  final List<Widget> secondary;

  final EdgeInsetsGeometry? padding;

  /// Soft time-of-day wash behind the brief.
  final bool atmosphere;

  /// Stagger module entrance when motion is enabled.
  final bool stagger;

  final Future<void> Function()? onRefresh;

  /// Optional sticky residual after [stage] collapses (scroll progress 0–1).
  final Widget Function(BuildContext context, double progress)? stickyBuilder;

  /// Inset for [stickyBuilder] overlay. Defaults to horizontal content pad.
  final EdgeInsetsGeometry? stickyPadding;

  /// Optionally centers the brief in a narrower reading column on wide
  /// canvases. Mobile layouts remain governed by [padding].
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final contentPadding =
        padding ??
        EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s8,
          AppSpacing.s16,
          AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
        );

    final columnChildren = <Widget>[
      greeting,
      const SizedBox(height: AppPageRhythm.module),
      stage,
      if (modules.isNotEmpty) ...[
        const SizedBox(height: AppPageRhythm.section),
        ..._interleave(modules, AppPageRhythm.module),
      ],
      if (secondary.isNotEmpty) ...[
        const SizedBox(height: AppPageRhythm.section),
        ..._interleave(secondary, AppPageRhythm.module),
      ],
    ];

    final contentChildren = stagger
        ? <Widget>[
            StaggeredColumn(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: columnChildren,
            ),
          ]
        : columnChildren;
    var listChildren = contentChildren;
    if (maxContentWidth case final width?) {
      listChildren = [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: contentChildren,
            ),
          ),
        ),
      ];
    }

    Widget body = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: contentPadding,
      children: listChildren,
    );

    if (onRefresh != null) {
      body = AppRefreshIndicator(onRefresh: onRefresh!, child: body);
    }

    final sticky = stickyBuilder;
    if (sticky != null) {
      final resolvedStickyPad =
          stickyPadding ??
          EdgeInsets.fromLTRB(
            contentPadding.resolve(Directionality.of(context)).left,
            AppSpacing.s4,
            contentPadding.resolve(Directionality.of(context)).right,
            0,
          );
      body = AppCollapsingScrollHost(
        padding: resolvedStickyPad,
        stickyBuilder: sticky,
        body: body,
      );
    }

    if (!atmosphere) return body;
    return AppAtmosphere(child: body);
  }

  static List<Widget> _interleave(List<Widget> items, double gap) {
    if (items.isEmpty) return const [];
    final out = <Widget>[items.first];
    for (var i = 1; i < items.length; i++) {
      out
        ..add(SizedBox(height: gap))
        ..add(items[i]);
    }
    return out;
  }
}

/// Brief composition for an unbounded repeated section.
///
/// Unlike [BriefScaffold], repeated rows are backed by a
/// [SliverChildBuilderDelegate] and are only built near the viewport. Use this
/// for Today/Review surfaces whose row count grows with user data.
class BriefLazyListScaffold extends StatelessWidget {
  const BriefLazyListScaffold({
    super.key,
    required this.greeting,
    required this.stage,
    required this.itemCount,
    required this.itemBuilder,
    this.modules = const <Widget>[],
    this.listHeader,
    this.padding,
    this.atmosphere = true,
    this.onRefresh,
    this.stickyBuilder,
    this.stickyPadding,
  });

  final Widget greeting;
  final Widget stage;
  final List<Widget> modules;
  final Widget? listHeader;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;
  final bool atmosphere;
  final Future<void> Function()? onRefresh;
  final Widget Function(BuildContext context, double progress)? stickyBuilder;
  final EdgeInsetsGeometry? stickyPadding;

  @override
  Widget build(BuildContext context) {
    final contentPadding =
        padding ??
        EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s8,
          AppSpacing.s16,
          AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
        );
    final resolved = contentPadding.resolve(Directionality.of(context));
    final headerChildren = <Widget>[
      greeting,
      const SizedBox(height: AppPageRhythm.module),
      stage,
      if (modules.isNotEmpty) ...[
        const SizedBox(height: AppPageRhythm.section),
        ...BriefScaffold._interleave(modules, AppPageRhythm.module),
      ],
      if (listHeader != null) ...[
        const SizedBox(height: AppPageRhythm.module),
        listHeader!,
      ],
    ];

    Widget body = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            resolved.left,
            resolved.top,
            resolved.right,
            itemCount == 0 ? resolved.bottom : 0,
          ),
          sliver: SliverList(delegate: SliverChildListDelegate(headerChildren)),
        ),
        if (itemCount > 0)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              resolved.left,
              AppPageRhythm.module,
              resolved.right,
              resolved.bottom,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: EdgeInsets.only(
                    bottom: index == itemCount - 1 ? 0 : AppPageRhythm.module,
                  ),
                  child: itemBuilder(context, index),
                ),
                childCount: itemCount,
              ),
            ),
          ),
      ],
    );

    if (onRefresh != null) {
      body = AppRefreshIndicator(onRefresh: onRefresh!, child: body);
    }
    final sticky = stickyBuilder;
    if (sticky != null) {
      final resolvedStickyPad =
          stickyPadding ??
          EdgeInsets.fromLTRB(
            resolved.left,
            AppSpacing.s4,
            resolved.right,
            AppSpacing.s0,
          );
      body = AppCollapsingScrollHost(
        padding: resolvedStickyPad,
        stickyBuilder: sticky,
        body: body,
      );
    }
    if (!atmosphere) return body;
    return AppAtmosphere(child: body);
  }
}
