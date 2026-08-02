import 'package:flutter/widgets.dart';

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
    this.minTileWidth = AppControlWidths.bentoTile,
  }) : assert(maxColumns > 0),
       assert(minTileWidth > 0);

  final List<AdaptiveSummaryTile> items;
  final double gap;
  final int maxColumns;

  /// Minimum readable module width at the default text scale. Dynamic Type
  /// increases this budget progressively rather than collapsing every wide
  /// desktop canvas to one column at a fixed scale threshold.
  final double minTileWidth;

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
    if (!width.isFinite) return 1;
    final scale = textScale.clamp(1.0, 2.5);
    final effectiveMinWidth = minTileWidth * (1 + (scale - 1) * 0.45);
    final fitting = ((width + gap) / (effectiveMinWidth + gap)).floor();
    return fitting.clamp(1, maxColumns);
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
      final span = switch (tile.role) {
        AdaptiveSummaryTileRole.standard => 1,
        AdaptiveSummaryTileRole.supporting => columns < 3 ? columns : 1,
        AdaptiveSummaryTileRole.featured => columns.clamp(1, 2),
        AdaptiveSummaryTileRole.continuous => columns,
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
    this.role = AdaptiveSummaryTileRole.standard,
  });

  final Widget child;
  final AdaptiveSummaryTileRole role;
}

/// Content priority supplied by a feature; column spans remain design-system
/// owned and adapt to width and text scale.
enum AdaptiveSummaryTileRole {
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
  continuous,
}

class _PackedSummaryTile {
  const _PackedSummaryTile({required this.tile, required this.span});

  final AdaptiveSummaryTile tile;
  final int span;
}
