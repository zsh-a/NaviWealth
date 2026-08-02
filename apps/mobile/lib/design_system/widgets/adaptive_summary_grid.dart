import 'package:flutter/widgets.dart';

import '../tokens/breakpoints.dart';
import '../tokens/dimens_tokens.dart';

/// A content-ordered Bento layout for bounded overview modules.
///
/// Compact surfaces and enlarged text stay single-column. Wider containers
/// progressively gain columns without changing reading or traversal order.
/// This widget only arranges children; it deliberately adds no card, tint, or
/// backdrop effect of its own.
class AdaptiveSummaryGrid extends StatelessWidget {
  const AdaptiveSummaryGrid({
    super.key,
    required this.items,
    this.gap = AppPageRhythm.module,
    this.maxColumns = 3,
    this.largeTextScaleThreshold = 1.4,
  }) : assert(maxColumns > 0),
       assert(largeTextScaleThreshold >= 1);

  final List<AdaptiveSummaryTile> items;
  final double gap;
  final int maxColumns;

  /// Above this effective scale, scanability wins over density.
  final double largeTextScaleThreshold;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = _columnCount(width, textScale);
        if (columns == 1 || !width.isFinite) {
          return _singleColumn();
        }

        final columnWidth = (width - gap * (columns - 1)) / columns;
        final rows = _packRows(columns);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
              if (rowIndex > 0) SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var itemIndex = 0;
                    itemIndex < rows[rowIndex].length;
                    itemIndex++
                  ) ...[
                    if (itemIndex > 0) SizedBox(width: gap),
                    SizedBox(
                      width:
                          columnWidth * rows[rowIndex][itemIndex].span +
                          gap * (rows[rowIndex][itemIndex].span - 1),
                      child: rows[rowIndex][itemIndex].tile.child,
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  int _columnCount(double width, double textScale) {
    if (!width.isFinite ||
        textScale >= largeTextScaleThreshold ||
        width < Breakpoints.contentThreeColumn) {
      return 1;
    }
    if (width < Breakpoints.contentTwoColumn) {
      return maxColumns.clamp(1, 2);
    }
    return maxColumns.clamp(1, 3);
  }

  Widget _singleColumn() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < items.length; index++) ...[
        if (index > 0) SizedBox(height: gap),
        items[index].child,
      ],
    ],
  );

  List<List<_PackedSummaryTile>> _packRows(int columns) {
    final rows = <List<_PackedSummaryTile>>[];
    var row = <_PackedSummaryTile>[];
    var used = 0;

    for (final tile in items) {
      final span = switch (tile.span) {
        AdaptiveSummaryTileSpan.standard => 1,
        AdaptiveSummaryTileSpan.supporting => columns < 3 ? columns : 1,
        AdaptiveSummaryTileSpan.featured => columns.clamp(1, 2),
        AdaptiveSummaryTileSpan.full => columns,
      };
      if (used > 0 && used + span > columns) {
        rows.add(row);
        row = <_PackedSummaryTile>[];
        used = 0;
      }
      row.add(_PackedSummaryTile(tile: tile, span: span));
      used += span;
      if (used == columns) {
        rows.add(row);
        row = <_PackedSummaryTile>[];
        used = 0;
      }
    }
    if (row.isNotEmpty) rows.add(row);
    return rows;
  }
}

/// A child and its preferred width in [AdaptiveSummaryGrid].
class AdaptiveSummaryTile {
  const AdaptiveSummaryTile({
    required this.child,
    this.span = AdaptiveSummaryTileSpan.standard,
  });

  final Widget child;
  final AdaptiveSummaryTileSpan span;
}

enum AdaptiveSummaryTileSpan {
  /// One column on every multi-column layout.
  standard,

  /// A quiet supporting rail on three-column canvases.
  ///
  /// Two-column canvases keep it full-width so a narrow chart or primary
  /// module is not forced into the remaining half of the row.
  supporting,

  /// Two columns when available; useful for one primary overview module.
  featured,

  /// A complete row, reserved for long-form or repeated content.
  full,
}

class _PackedSummaryTile {
  const _PackedSummaryTile({required this.tile, required this.span});

  final AdaptiveSummaryTile tile;
  final int span;
}
