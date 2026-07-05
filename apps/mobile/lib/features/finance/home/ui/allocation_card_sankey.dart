part of 'allocation_card.dart';

class _AllocationSankeyChart extends StatelessWidget {
  const _AllocationSankeyChart({
    required this.assetAllocs,
    required this.liabilityAlloc,
    required this.snapshot,
    required this.height,
    required this.onTap,
  });

  final List<CategoryAllocation> assetAllocs;
  final CategoryAllocation? liabilityAlloc;
  final DashboardSnapshot snapshot;
  final double height;
  final void Function(CategoryAllocation) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final palette = ChartPalette.of(context);
    final valueAxis = ValueAxis.currency(currencyCode: snapshot.baseCurrency);
    final flows = <_SankeyFlow>[
      for (var i = 0; i < assetAllocs.length; i++)
        if (assetAllocs[i].totalInBase.amount.toDouble() > 0)
          _SankeyFlow(
            label: AssetCategoryVisuals.label(l10n, assetAllocs[i].category),
            value: assetAllocs[i].totalInBase.amount.toDouble(),
            valueLabel: valueAxis.formatValue(
              assetAllocs[i].totalInBase.amount.toDouble(),
            ),
            color: palette.accentAt(i),
            allocation: assetAllocs[i],
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final liabilityValue =
        liabilityAlloc?.totalInBase.amount.toDouble().abs() ?? 0;

    if (flows.isEmpty && liabilityValue == 0) {
      return SizedBox(
        height: height,
        child: const EmptyChartPlaceholder(icon: FLucideIcons.folderTree),
      );
    }

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final hit = _SankeyLayout.compute(
                size: Size(constraints.maxWidth, height),
                flows: flows,
                liabilityValue: liabilityValue,
              ).hitTest(details.localPosition, flows, liabilityAlloc);
              if (hit != null) onTap(hit);
            },
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _SankeyPainter(
                  flows: flows,
                  totalAssetsLabel: l10n.assetsAppBarTitle,
                  totalAssetsValueLabel: valueAxis.formatValue(
                    snapshot.totalAssets.amount.toDouble(),
                  ),
                  netWorthLabel: l10n.homeNetWorthTitle,
                  netWorthValue: snapshot.netWorth.amount
                      .toDouble()
                      .clamp(0.0, double.infinity)
                      .toDouble(),
                  netWorthValueLabel: valueAxis.formatValue(
                    snapshot.netWorth.amount.toDouble(),
                  ),
                  liabilityLabel: l10n.dashboardCategoryLiability,
                  liabilityValue: liabilityValue,
                  liabilityValueLabel: valueAxis.formatValue(liabilityValue),
                  liabilityAllocation: liabilityAlloc,
                  neutralColor: colors.mutedForeground,
                  profitColor: MarketColors.of(context).up,
                  lossColor: MarketColors.of(context).down,
                  labelColor: colors.foreground,
                  valueColor: colors.mutedForeground,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SankeyFlow {
  const _SankeyFlow({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.color,
    required this.allocation,
  });

  final String label;
  final double value;
  final String valueLabel;
  final Color color;
  final CategoryAllocation allocation;
}

class _SankeyLayout {
  const _SankeyLayout({
    required this.sourceRects,
    required this.assetRect,
    required this.netWorthRect,
    required this.liabilityRect,
    required this.assetOutRect,
    required this.netWorthInRect,
    required this.liabilityOutRect,
    required this.liabilityInRect,
  });

  final List<Rect> sourceRects;
  final Rect assetRect;
  final Rect netWorthRect;
  final Rect? liabilityRect;
  final Rect assetOutRect;
  final Rect netWorthInRect;
  final Rect? liabilityOutRect;
  final Rect? liabilityInRect;

  static _SankeyLayout compute({
    required Size size,
    required List<_SankeyFlow> flows,
    required double liabilityValue,
  }) {
    const nodeWidth = 12.0;
    const top = 16.0;
    final bottom = size.height - 16.0;
    final available = math.max(1.0, bottom - top);
    final totalAssets = flows.fold<double>(0, (sum, f) => sum + f.value);
    final total = math.max(totalAssets, 1);
    final gap = flows.length > 1 ? 8.0 : 0.0;
    final sourceAvailable = math.max(
      1.0,
      available - gap * math.max(0, flows.length - 1),
    );
    final sourceRects = <Rect>[];
    var cursor = top;
    for (final flow in flows) {
      final h = math.max(12.0, sourceAvailable * flow.value / total);
      sourceRects.add(Rect.fromLTWH(0, cursor, nodeWidth, h));
      cursor += h + gap;
    }

    final centerX = size.width * 0.58;
    final rightX = size.width - nodeWidth;
    final assetRect = Rect.fromLTWH(centerX, top, nodeWidth, available);
    final liabilityRatio = liabilityValue <= 0 ? 0.0 : liabilityValue / total;
    final liabilityHeight = liabilityValue <= 0
        ? 0.0
        : math.max(24.0, available * liabilityRatio);
    final netWorthHeight = liabilityValue <= 0
        ? available
        : math.max(24.0, available - liabilityHeight - 10);
    final netWorthRect = Rect.fromLTWH(rightX, top, nodeWidth, netWorthHeight);
    final liabilityRect = liabilityValue <= 0
        ? null
        : Rect.fromLTWH(
            rightX,
            bottom - liabilityHeight,
            nodeWidth,
            liabilityHeight,
          );
    final assetOutRect = Rect.fromLTWH(centerX + nodeWidth, top, 1, available);
    final netWorthInRect = Rect.fromLTWH(rightX - 1, top, 1, netWorthHeight);
    final liabilityOutRect = liabilityValue <= 0
        ? null
        : Rect.fromLTWH(
            centerX + nodeWidth,
            bottom - liabilityHeight,
            1,
            liabilityHeight,
          );
    final liabilityInRect = liabilityRect == null
        ? null
        : Rect.fromLTWH(rightX - 1, liabilityRect.top, 1, liabilityHeight);
    return _SankeyLayout(
      sourceRects: sourceRects,
      assetRect: assetRect,
      netWorthRect: netWorthRect,
      liabilityRect: liabilityRect,
      assetOutRect: assetOutRect,
      netWorthInRect: netWorthInRect,
      liabilityOutRect: liabilityOutRect,
      liabilityInRect: liabilityInRect,
    );
  }

  CategoryAllocation? hitTest(
    Offset point,
    List<_SankeyFlow> flows,
    CategoryAllocation? liabilityAllocation,
  ) {
    for (var i = 0; i < sourceRects.length && i < flows.length; i++) {
      final hitRect = Rect.fromLTRB(
        sourceRects[i].left,
        sourceRects[i].top - 4,
        assetRect.left,
        sourceRects[i].bottom + 4,
      );
      if (hitRect.contains(point)) return flows[i].allocation;
    }
    if (liabilityAllocation != null &&
        liabilityRect != null &&
        Rect.fromLTRB(
          assetRect.right,
          liabilityRect!.top - 8,
          liabilityRect!.right,
          liabilityRect!.bottom + 8,
        ).contains(point)) {
      return liabilityAllocation;
    }
    return null;
  }
}

class _SankeyPainter extends CustomPainter {
  const _SankeyPainter({
    required this.flows,
    required this.totalAssetsLabel,
    required this.totalAssetsValueLabel,
    required this.netWorthLabel,
    required this.netWorthValue,
    required this.netWorthValueLabel,
    required this.liabilityLabel,
    required this.liabilityValue,
    required this.liabilityValueLabel,
    required this.liabilityAllocation,
    required this.neutralColor,
    required this.profitColor,
    required this.lossColor,
    required this.labelColor,
    required this.valueColor,
  });

  final List<_SankeyFlow> flows;
  final String totalAssetsLabel;
  final String totalAssetsValueLabel;
  final String netWorthLabel;
  final double netWorthValue;
  final String netWorthValueLabel;
  final String liabilityLabel;
  final double liabilityValue;
  final String liabilityValueLabel;
  final CategoryAllocation? liabilityAllocation;
  final Color neutralColor;
  final Color profitColor;
  final Color lossColor;
  final Color labelColor;
  final Color valueColor;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _SankeyLayout.compute(
      size: size,
      flows: flows,
      liabilityValue: liabilityValue,
    );
    final totalAssets = flows.fold<double>(0, (sum, f) => sum + f.value);
    final nodePaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < flows.length; i++) {
      final flow = flows[i];
      final source = layout.sourceRects[i];
      final targetHeight =
          layout.assetRect.height * (flow.value / math.max(totalAssets, 1));
      final previous = flows
          .take(i)
          .fold<double>(
            0,
            (sum, f) => sum + f.value / math.max(totalAssets, 1),
          );
      final target = Rect.fromLTWH(
        layout.assetRect.left,
        layout.assetRect.top + layout.assetRect.height * previous,
        layout.assetRect.width,
        targetHeight,
      );
      _drawRibbon(
        canvas,
        source,
        target,
        flow.color.withValues(alpha: AppOpacity.muted),
      );
      nodePaint.color = flow.color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(source, const Radius.circular(AppRadius.xs)),
        nodePaint,
      );
      _drawLabel(
        canvas,
        Offset(source.right + 8, source.top - 1),
        flow.label,
        flow.valueLabel,
        size.width * 0.34,
      );
    }

    nodePaint.color = neutralColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        layout.assetRect,
        const Radius.circular(AppRadius.xs),
      ),
      nodePaint,
    );
    _drawLabel(
      canvas,
      Offset(layout.assetRect.left - 54, layout.assetRect.top),
      totalAssetsLabel,
      totalAssetsValueLabel,
      50,
      align: TextAlign.right,
    );

    final netWorthOutHeight = liabilityValue <= 0
        ? layout.assetRect.height
        : layout.netWorthRect.height;
    final netWorthOut = Rect.fromLTWH(
      layout.assetOutRect.left,
      layout.assetRect.top,
      1,
      netWorthOutHeight,
    );
    _drawRibbon(
      canvas,
      netWorthOut,
      layout.netWorthInRect,
      profitColor.withValues(alpha: AppOpacity.muted),
    );
    nodePaint.color = profitColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        layout.netWorthRect,
        const Radius.circular(AppRadius.xs),
      ),
      nodePaint,
    );
    _drawLabel(
      canvas,
      Offset(layout.netWorthRect.left - 96, layout.netWorthRect.top),
      netWorthLabel,
      netWorthValueLabel,
      88,
      align: TextAlign.right,
    );

    if (liabilityValue > 0 &&
        layout.liabilityRect != null &&
        layout.liabilityOutRect != null &&
        layout.liabilityInRect != null) {
      _drawRibbon(
        canvas,
        layout.liabilityOutRect!,
        layout.liabilityInRect!,
        lossColor.withValues(alpha: AppOpacity.muted),
      );
      nodePaint.color = lossColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          layout.liabilityRect!,
          const Radius.circular(AppRadius.xs),
        ),
        nodePaint,
      );
      _drawLabel(
        canvas,
        Offset(layout.liabilityRect!.left - 96, layout.liabilityRect!.top),
        liabilityLabel,
        liabilityValueLabel,
        88,
        align: TextAlign.right,
      );
    }
  }

  void _drawRibbon(Canvas canvas, Rect from, Rect to, Color color) {
    final path = Path()
      ..moveTo(from.right, from.top)
      ..cubicTo(
        from.right + 48,
        from.top,
        to.left - 48,
        to.top,
        to.left,
        to.top,
      )
      ..lineTo(to.left, to.bottom)
      ..cubicTo(
        to.left - 48,
        to.bottom,
        from.right + 48,
        from.bottom,
        from.right,
        from.bottom,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawLabel(
    Canvas canvas,
    Offset offset,
    String label,
    String value,
    double maxWidth, {
    TextAlign align = TextAlign.left,
  }) {
    final title = TextPainter(
      text: TextSpan(
        text: label,
        style: TypographyTokens.numericCaptionStrong.copyWith(
          color: labelColor,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    title.paint(canvas, offset);
    final subtitle = TextPainter(
      text: TextSpan(
        text: value,
        style: TypographyTokens.numericCaption.copyWith(color: valueColor),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    subtitle.paint(canvas, offset.translate(0, title.height + 1));
  }

  @override
  bool shouldRepaint(covariant _SankeyPainter oldDelegate) =>
      oldDelegate.flows != flows ||
      oldDelegate.liabilityValue != liabilityValue ||
      oldDelegate.netWorthValue != netWorthValue;
}
