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

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../tokens/breakpoints.dart';
import '../../tokens/dimens_tokens.dart';
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
        final padding = isWide
            ? const EdgeInsets.all(24)
            : const EdgeInsets.all(16);
        const allocation = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 18, radius: 4),
              SizedBox(height: AppSpacing.s16),
              Center(child: SkeletonBox(width: 200, height: 200, radius: 9999)),
              SizedBox(height: AppSpacing.s16),
              SkeletonBox(height: 14),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(height: 14),
            ],
          ),
        );
        const trend = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 18, radius: 4),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 32, radius: 8),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 220, radius: 8),
            ],
          ),
        );
        const header = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 88, height: 14, radius: 4),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 220, height: 36, radius: 8),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 180, height: 12, radius: 4),
            ],
          ),
        );
        if (isWide) {
          return ListView(
            padding: padding,
            children: const [
              header,
              SizedBox(height: AppSpacing.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: allocation),
                  SizedBox(width: AppSpacing.s16),
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
            SizedBox(height: AppSpacing.s12),
            allocation,
            SizedBox(height: AppSpacing.s12),
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
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SkeletonBox(width: 36, height: 36, radius: 9999),
          SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: AppSpacing.s6),
                SkeletonBox(width: 88, height: 12),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.s12),
          SkeletonBox(width: 80, height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SkeletonBox(width: 100, height: 18),
        ),
        FCard.raw(
          child: Column(
            children: [
              for (var i = 0; i < rowCount; i++) ...[
                _row(),
                if (i != rowCount - 1) const FDivider(),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SkeletonBox(width: 120, height: 18),
        ),
        FCard.raw(child: Column(children: [_row(), const FDivider(), _row()])),
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
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonCard(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 88, height: 14, radius: 4),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 220, height: 32, radius: 8),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 160, height: 12, radius: 4),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 80, height: 14, radius: 4),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 18),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(height: 18),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 16, radius: 4),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 180, radius: 8),
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
        SkeletonBox(width: 160, height: 20, radius: 4),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(width: 240, height: 14, radius: 4),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: 40, radius: 8),
        SizedBox(height: AppSpacing.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SkeletonBox(width: 120, height: 14),
            SkeletonBox(width: 120, height: 18),
          ],
        ),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: 220, radius: 8),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: 56, radius: 8),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(height: 56, radius: 8),
      ],
    );
    const right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonCard(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 16, radius: 4),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(height: 14),
              SizedBox(height: AppSpacing.s4),
              SkeletonBox(height: 14),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s24),
        SkeletonCard(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16, radius: 4),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 140, radius: 8),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide ? const EdgeInsets.all(24) : const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 18),
              SizedBox(height: AppSpacing.s12),
              Center(child: SkeletonBox(width: 200, height: 200, radius: 9999)),
              SizedBox(height: AppSpacing.s16),
              SkeletonBox(height: 14),
              SizedBox(height: AppSpacing.s4),
              SkeletonBox(height: 14, width: 220),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 16),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 200, height: 28, radius: 8),
              SizedBox(height: AppSpacing.s4),
              SkeletonBox(width: 160, height: 12),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 180, radius: 8),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mirrors `CashFlowPage`: period chips + a KPI row, then the income/expense
/// charts panel beside the category-mix panel (stacked on narrow widths).
class CashFlowSkeleton extends StatelessWidget {
  const CashFlowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    const kpi = SkeletonCard(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 72, height: 12, radius: 4),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 120, height: 24, radius: 8),
        ],
      ),
    );
    const charts = SkeletonCard(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 140, height: 16, radius: 4),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(height: 180, radius: 8),
          SizedBox(height: AppSpacing.s20),
          SkeletonBox(width: 140, height: 16, radius: 4),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(height: 220, radius: 8),
        ],
      ),
    );
    const category = SkeletonCard(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120, height: 16, radius: 4),
          SizedBox(height: AppSpacing.s12),
          Center(child: SkeletonBox(width: 160, height: 160, radius: 9999)),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(height: 14),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(height: 14),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(height: 14),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide ? const EdgeInsets.all(24) : const EdgeInsets.all(16),
          children: const [
            Row(
              children: [
                SkeletonBox(width: 64, height: 32, radius: 9999),
                SizedBox(width: AppSpacing.s8),
                SkeletonBox(width: 64, height: 32, radius: 9999),
                SizedBox(width: AppSpacing.s8),
                SkeletonBox(width: 64, height: 32, radius: 9999),
              ],
            ),
            SizedBox(height: AppSpacing.s16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: kpi),
                  SizedBox(width: AppSpacing.s12),
                  Expanded(child: kpi),
                  SizedBox(width: AppSpacing.s12),
                  Expanded(child: kpi),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.s16),
            ResponsiveTwoColumn(left: charts, right: category),
          ],
        );
      },
    );
  }
}

/// Mirrors `DividendCenterPage`: a KPI metric grid, a holdings-ranking card,
/// a forecast strip, and the history-timeline card.
class DividendCenterSkeleton extends StatelessWidget {
  const DividendCenterSkeleton({super.key});

  static Widget _metric() => const SkeletonCard(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 64, height: 12, radius: 4),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(width: 96, height: 22, radius: 8),
      ],
    ),
  );

  static Widget _listCard(int rows) => SkeletonCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(width: 140, height: 16, radius: 4),
        const SizedBox(height: AppSpacing.s12),
        for (var i = 0; i < rows; i++) ...[
          if (i != 0) const SizedBox(height: AppSpacing.s12),
          const SkeletonBox(height: 16),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide ? const EdgeInsets.all(24) : const EdgeInsets.all(16),
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _metric()),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(child: _metric()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _metric()),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(child: _metric()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            _listCard(6),
            const SizedBox(height: AppSpacing.s16),
            const SkeletonCard(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SkeletonBox(width: 24, height: 24, radius: 9999),
                  SizedBox(width: AppSpacing.s12),
                  Expanded(child: SkeletonBox(height: 42, radius: 8)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            _listCard(5),
          ],
        );
      },
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
            padding: const EdgeInsets.all(16),
            children: const [
              _ChatBubbleSkeleton(alignEnd: false),
              SizedBox(height: AppSpacing.s12),
              _ChatBubbleSkeleton(alignEnd: true, lines: 1),
              SizedBox(height: AppSpacing.s12),
              _ChatBubbleSkeleton(alignEnd: false, lines: 3),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SkeletonBox(height: 48, radius: 16),
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.theme.colors.muted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: alignEnd
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < lines; i++) ...[
                if (i != 0) const SizedBox(height: AppSpacing.s6),
                SkeletonBox(width: 200.0 - (i * 24), height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
