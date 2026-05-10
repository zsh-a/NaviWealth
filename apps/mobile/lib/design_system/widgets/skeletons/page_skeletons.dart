/// Page-level skeleton templates that mirror each top-level surface's
/// resolved layout — stretched cards, hero blocks, list rows — so the
/// transition from "loading" to "data" lands without the page reflowing.
///
/// The shimmer cells re-use [SkeletonBox] / [SkeletonCard], which already
/// honor `MediaQuery.disableAnimations` and the design-system surface tones.
///
/// All page skeletons are wrapped in [PageSkeletonShell], which guarantees
/// the skeleton stays visible for at least [PageSkeletonShell.minDisplay]
/// before swapping to real data — under local-first reads (< 50ms typical)
/// a bare `loading: () => skeleton` would otherwise flash for a single
/// frame and read as a glitch. Callers feed it the resolved `data` widget
/// and the [AsyncValue]; the shell handles the timing.
library;

import 'package:flutter/material.dart';

import '../../tokens/breakpoints.dart';
import '../../tokens/radius_tokens.dart';
import '../../tokens/spacing_tokens.dart';
import '../responsive_two_column.dart';
import '../skeleton.dart';

/// Minimum visible time for a page-level skeleton. Shorter than this and
/// the human eye reads the swap as a flash rather than a hand-off.
const Duration _kMinSkeletonDisplay = Duration(milliseconds: 120);

/// Wraps an async builder so the skeleton phase is held for at least
/// [minDisplay] before the resolved widget swaps in. The data widget is
/// re-built on every frame once data is available — the shell only gates
/// the visibility of the skeleton itself.
class PageSkeletonShell<T> extends StatefulWidget {
  const PageSkeletonShell({
    super.key,
    required this.skeleton,
    required this.isLoading,
    required this.child,
    this.minDisplay = _kMinSkeletonDisplay,
  });

  /// Skeleton template to show while [isLoading] is true (or before
  /// [minDisplay] has elapsed).
  final Widget skeleton;

  /// Whether the underlying provider is still loading.
  final bool isLoading;

  /// Real content. Only shown once both [isLoading] is false **and** the
  /// minimum skeleton-display window has elapsed.
  final Widget child;

  /// Lower bound on how long the skeleton stays on screen. Defaults to
  /// 120ms — short enough not to feel slow, long enough not to flash.
  final Duration minDisplay;

  @override
  State<PageSkeletonShell<T>> createState() => _PageSkeletonShellState<T>();
}

class _PageSkeletonShellState<T> extends State<PageSkeletonShell<T>> {
  bool _minElapsed = false;

  @override
  void initState() {
    super.initState();
    _scheduleElapsed();
  }

  void _scheduleElapsed() {
    Future<void>.delayed(widget.minDisplay).then((_) {
      if (!mounted) return;
      setState(() => _minElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSkeleton = widget.isLoading || !_minElapsed;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: showSkeleton
          ? KeyedSubtree(
              key: const ValueKey('page-skeleton'),
              child: widget.skeleton,
            )
          : KeyedSubtree(key: const ValueKey('page-data'), child: widget.child),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-page templates
// ---------------------------------------------------------------------------

/// Mirrors `HomePage`: hero net-worth card on top, allocation pie + trend
/// chart side-by-side on wide breakpoints, stacked on mobile.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        final padding = isWide ? Spacing.pageWide : Spacing.pageMobile;
        const allocation = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 18, radius: Radii.xs),
              SizedBox(height: Spacing.s16),
              Center(
                child: SkeletonBox(width: 200, height: 200, radius: Radii.full),
              ),
              SizedBox(height: Spacing.s16),
              SkeletonBox(height: 14),
              SizedBox(height: Spacing.s8),
              SkeletonBox(height: 14),
            ],
          ),
        );
        const trend = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 18, radius: Radii.xs),
              SizedBox(height: Spacing.s12),
              SkeletonBox(height: 32, radius: Radii.sm),
              SizedBox(height: Spacing.s12),
              SkeletonBox(height: 220, radius: Radii.sm),
            ],
          ),
        );
        const header = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 88, height: 14, radius: Radii.xs),
              SizedBox(height: Spacing.s8),
              SkeletonBox(width: 220, height: 36, radius: Radii.sm),
              SizedBox(height: Spacing.s8),
              SkeletonBox(width: 180, height: 12, radius: Radii.xs),
            ],
          ),
        );
        if (isWide) {
          return ListView(
            padding: padding,
            children: const [
              header,
              SizedBox(height: Spacing.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: allocation),
                  SizedBox(width: Spacing.s16),
                  Expanded(child: trend),
                ],
              ),
            ],
          );
        }
        return ListView(
          padding: padding,
          children: const [
            header,
            SizedBox(height: Spacing.s12),
            allocation,
            SizedBox(height: Spacing.s12),
            trend,
          ],
        );
      },
    );
  }
}

/// Mirrors `AssetsPage`: section header + a card of repeated rows for the
/// manual-asset book and another for physical assets.
class AssetsListSkeleton extends StatelessWidget {
  const AssetsListSkeleton({super.key, this.rowCount = 3});

  final int rowCount;

  Widget _row() {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s12,
      ),
      child: Row(
        children: [
          SkeletonBox(width: 36, height: 36, radius: Radii.full),
          SizedBox(width: Spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: Spacing.s6),
                SkeletonBox(width: 88, height: 12),
              ],
            ),
          ),
          SizedBox(width: Spacing.s12),
          SkeletonBox(width: 80, height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: Spacing.pageMobile,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.s8),
          child: SkeletonBox(width: 100, height: 18),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rowCount; i++) ...[
                _row(),
                if (i != rowCount - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: Spacing.s12),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.s8),
          child: SkeletonBox(width: 120, height: 18),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [_row(), const Divider(height: 1), _row()]),
        ),
      ],
    );
  }
}

/// Mirrors the equity / physical asset detail layout: hero summary card,
/// holding / valuation block, and a 30-day chart placeholder.
class AssetDetailSkeleton extends StatelessWidget {
  const AssetDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: Spacing.pageMobile,
      children: const [
        SkeletonCard(
          padding: Spacing.cardHero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 88, height: 14, radius: Radii.xs),
              SizedBox(height: Spacing.s8),
              SkeletonBox(width: 220, height: 32, radius: Radii.sm),
              SizedBox(height: Spacing.s8),
              SkeletonBox(width: 160, height: 12, radius: Radii.xs),
            ],
          ),
        ),
        SizedBox(height: Spacing.s12),
        SkeletonCard(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 80, height: 14, radius: Radii.xs),
              SizedBox(height: Spacing.s12),
              SkeletonBox(height: 18),
              SizedBox(height: Spacing.s8),
              SkeletonBox(height: 18),
            ],
          ),
        ),
        SizedBox(height: Spacing.s12),
        SkeletonCard(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 16, radius: Radii.xs),
              SizedBox(height: Spacing.s12),
              SkeletonBox(height: 180, radius: Radii.sm),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mirrors `AnalyticsPage`: equity-allocation column on the left, risk +
/// benchmark column on the right; collapses to a single column on mobile.
class AnalyticsSkeleton extends StatelessWidget {
  const AnalyticsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    const left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(width: 160, height: 20, radius: Radii.xs),
        SizedBox(height: Spacing.s8),
        SkeletonBox(width: 240, height: 14, radius: Radii.xs),
        SizedBox(height: Spacing.s16),
        SkeletonBox(height: 40, radius: Radii.sm),
        SizedBox(height: Spacing.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SkeletonBox(width: 120, height: 14),
            SkeletonBox(width: 120, height: 18),
          ],
        ),
        SizedBox(height: Spacing.s16),
        SkeletonBox(height: 220, radius: Radii.sm),
        SizedBox(height: Spacing.s16),
        SkeletonBox(height: 56, radius: Radii.sm),
        SizedBox(height: Spacing.s8),
        SkeletonBox(height: 56, radius: Radii.sm),
      ],
    );
    const right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonCard(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 16, radius: Radii.xs),
              SizedBox(height: Spacing.s8),
              SkeletonBox(height: 14),
              SizedBox(height: Spacing.s4),
              SkeletonBox(height: 14),
            ],
          ),
        ),
        SizedBox(height: Spacing.s24),
        SkeletonCard(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16, radius: Radii.xs),
              SizedBox(height: Spacing.s12),
              SkeletonBox(height: 140, radius: Radii.sm),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide ? Spacing.pageWide : Spacing.pageMobile,
          children: const [ResponsiveTwoColumn(left: left, right: right)],
        );
      },
    );
  }
}

/// Mirrors `FirePage`: hero progress card with a circular gauge, plus the
/// secondary scenario / sensitivity blocks.
class FireSkeleton extends StatelessWidget {
  const FireSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: Spacing.pageMobile,
      children: const [
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 18),
              SizedBox(height: Spacing.s12),
              Center(
                child: SkeletonBox(width: 200, height: 200, radius: Radii.full),
              ),
              SizedBox(height: Spacing.s16),
              SkeletonBox(height: 14),
              SizedBox(height: Spacing.s4),
              SkeletonBox(height: 14, width: 220),
            ],
          ),
        ),
        SizedBox(height: Spacing.s12),
        SkeletonCard(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 16),
              SizedBox(height: Spacing.s8),
              SkeletonBox(width: 200, height: 28, radius: Radii.sm),
              SizedBox(height: Spacing.s4),
              SkeletonBox(width: 160, height: 12),
            ],
          ),
        ),
        SizedBox(height: Spacing.s12),
        SkeletonCard(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16),
              SizedBox(height: Spacing.s12),
              SkeletonBox(height: 180, radius: Radii.sm),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mirrors `AiChatPage` while the message stream is loading — three stacked
/// bubble placeholders alternating sides, plus a composer placeholder bar.
class AiChatSkeleton extends StatelessWidget {
  const AiChatSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: Spacing.pageMobile,
            children: const [
              _ChatBubbleSkeleton(alignEnd: false),
              SizedBox(height: Spacing.s12),
              _ChatBubbleSkeleton(alignEnd: true, lines: 1),
              SizedBox(height: Spacing.s12),
              _ChatBubbleSkeleton(alignEnd: false, lines: 3),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Spacing.s12,
            vertical: Spacing.s8,
          ),
          child: SkeletonBox(height: 48, radius: Radii.lg),
        ),
      ],
    );
  }
}

class _ChatBubbleSkeleton extends StatelessWidget {
  const _ChatBubbleSkeleton({required this.alignEnd, this.lines = 2});

  final bool alignEnd;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          padding: const EdgeInsets.all(Spacing.s12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Column(
            crossAxisAlignment: alignEnd
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < lines; i++) ...[
                if (i != 0) const SizedBox(height: Spacing.s6),
                SkeletonBox(width: 200.0 - (i * 24), height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
