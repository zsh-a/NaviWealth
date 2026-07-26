part of 'tool_invocation_renderers.dart';

// ---------------------------------------------------------------------------
// get_asset_allocation → donut + weight list.
// Payload shape: { buckets: [{bucket_dim, bucket_key, currency,
//   total_cost_minor (string), position_count (int), weight (double)}],
//   count, source, note }
// Weights are normalised per-currency (sum=1 within a currency); when the
// caller mixes multiple currencies we split into per-currency groups so
// the donut stays interpretable.
// ---------------------------------------------------------------------------

class AssetAllocationView extends StatelessWidget {
  const AssetAllocationView({super.key, required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final m = _asMap(output);
    final l10n = AppLocalizations.of(context);
    final raw = _asList(m?['buckets']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return _EmptyHint(text: l10n.aiToolHoldingsEmpty);
    }
    final colors = context.theme.colors;
    final palette = <Color>[
      colors.primary,
      colors.secondary,
      colors.mutedForeground,
      colors.primary.withValues(alpha: AppOpacity.muted),
      colors.secondary.withValues(alpha: AppOpacity.medium),
      colors.border,
    ];

    // Group by currency so the donut totals are meaningful.
    final byCurrency = <String, List<_AllocBucket>>{};
    for (final b in raw) {
      final mb = _asMap(b);
      if (mb == null) continue;
      final bucket = _AllocBucket.fromJson(mb);
      if (bucket == null) continue;
      byCurrency
          .putIfAbsent(bucket.currency, () => <_AllocBucket>[])
          .add(bucket);
    }
    if (byCurrency.isEmpty) {
      return _EmptyHint(text: l10n.aiToolHoldingsDataMalformed);
    }

    return ToolResultSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in byCurrency.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: _AllocBlock(
                currency: entry.key,
                buckets: entry.value,
                palette: palette,
              ),
            ),
        ],
      ),
    );
  }
}

class _AllocBucket {
  const _AllocBucket({
    required this.key,
    required this.currency,
    required this.totalMinor,
    required this.positions,
    required this.weight,
  });
  final String key;
  final String currency;
  final int totalMinor;
  final int positions;
  final double weight;

  static _AllocBucket? fromJson(Map<String, Object?> m) {
    final key = _asString(m['bucket_key']);
    final currency = _asString(m['currency']);
    if (key == null || currency == null) return null;
    return _AllocBucket(
      key: key,
      currency: currency,
      totalMinor: int.tryParse(_asString(m['total_cost_minor']) ?? '0') ?? 0,
      positions: (m['position_count'] is int)
          ? m['position_count']! as int
          : (int.tryParse(_asString(m['position_count']) ?? '0') ?? 0),
      weight: _asDouble(m['weight']) ?? 0.0,
    );
  }
}

class _AllocBlock extends StatelessWidget {
  const _AllocBlock({
    required this.currency,
    required this.buckets,
    required this.palette,
  });
  final String currency;
  final List<_AllocBucket> buckets;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final sorted = [...buckets]..sort((a, b) => b.weight.compareTo(a.weight));
    final fmt = NumberFormat.decimalPattern();
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(
          alpha: AppOpacity.disabled,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(currency, style: context.bodyCaptionStyle),
          const SizedBox(height: AppSpacing.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: AppControlWidths.aiDonut,
                height: AppControlWidths.aiDonut,
                child: CustomPaint(
                  painter: _DonutPainter(
                    slices: sorted,
                    palette: palette,
                    background: context.theme.colors.background,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < sorted.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s2,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: palette[i % palette.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s6),
                            Expanded(
                              child: Text(
                                sorted[i].key,
                                style: context.theme.typography.body.xs,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              formatters.percent(
                                sorted[i].weight,
                                decimalDigits: 1,
                              ),
                              style: context.captionStyle.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.aiToolTotalCostSummary(
              fmt.format(
                sorted.fold<int>(0, (a, b) => a + b.totalMinor) / 100.0,
              ),
              sorted.length,
            ),
            style: context.microCaptionStyle,
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.palette,
    required this.background,
  });
  final List<_AllocBucket> slices;
  final List<Color> palette;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, b) => a + b.weight);
    if (total <= 0) return;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 1,
    );
    var start = -math.pi / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < slices.length; i++) {
      final sweep = (slices[i].weight / total) * math.pi * 2;
      stroke.color = palette[i % palette.length];
      canvas.drawArc(rect.deflate(6), start, sweep, false, stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.palette != palette;
}
