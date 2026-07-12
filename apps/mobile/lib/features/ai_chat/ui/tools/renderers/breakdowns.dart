part of 'tool_invocation_renderers.dart';

// ---------------------------------------------------------------------------
// get_*_breakdown -> compact pie + top 3 categories.
// Payload: { total, buckets: [ { label, cost_basis, share, currency } ] }
// ---------------------------------------------------------------------------

class _BreakdownView extends StatelessWidget {
  const _BreakdownView({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final raw = _asList(outMap['buckets']) ?? const <Object?>[];
    final buckets = <_BreakdownBucket>[];
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) continue;
      final label = _asString(m['label']) ?? 'unknown';
      final cost = _asDouble(m['cost_basis']) ?? 0;
      final share = _asDouble(m['share']) ?? 0;
      final currency = _asString(m['currency']) ?? 'CNY';
      buckets.add(
        _BreakdownBucket(
          label: label,
          cost: cost,
          share: share,
          currency: currency,
        ),
      );
    }
    if (buckets.isEmpty) {
      return _EmptyResult(message: l10n.aiToolBreakdownCostEmpty);
    }
    buckets.sort((a, b) => b.cost.compareTo(a.cost));
    final palette = ChartPalette.of(context);
    final top = buckets.take(3).toList();

    final slices = <Slice>[
      for (var i = 0; i < buckets.length; i++)
        Slice(
          label: buckets[i].label,
          value: buckets[i].share.clamp(0.0, 1.0) * 100,
          colorOverride: palette.accentAt(i),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: AppControlWidths.aiCompactColumn,
            height: AppControlWidths.aiCompactColumn,
            child: NwPieChart(
              slices: slices,
              hole: 0.62,
              minLabelPercent: 100, // hide in-slice labels for mini view
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < top.length; i++)
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
                            color: palette.accentAt(i),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s6),
                        Expanded(
                          child: Text(
                            top[i].label,
                            style: context.captionStyle.copyWith(
                              color: context.theme.colors.foreground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          NumberFormat.percentPattern().format(
                            top[i].share.clamp(0.0, 1.0),
                          ),
                          style: context.captionStyle.copyWith(
                            color: context.theme.colors.foreground,
                            fontFeatures: TypographyTokens.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (buckets.length > top.length)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s4),
                    child: Text(
                      l10n.aiToolOtherCategoriesSummary(
                        buckets.length - top.length,
                        NumberFormat.percentPattern().format(
                          buckets
                              .skip(top.length)
                              .fold<double>(0, (s, b) => s + b.share)
                              .clamp(0.0, 1.0),
                        ),
                      ),
                      style: context.microCaptionStyle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownBucket {
  const _BreakdownBucket({
    required this.label,
    required this.cost,
    required this.share,
    required this.currency,
  });
  final String label;
  final double cost;
  final double share;
  final String currency;
}

// ---------------------------------------------------------------------------
// get_risk_alerts -> severity-tinted list.
// Payload: { alerts: [ { kind, asset_id?, symbol?, industry?, share,
//           threshold, severity, message } ] }
// ---------------------------------------------------------------------------

class _RiskAlertList extends StatelessWidget {
  const _RiskAlertList({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final raw = _asList(outMap['alerts']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return _EmptyResult(message: l10n.aiToolRiskAlertsEmpty, positive: true);
    }
    final alerts = <_RiskAlert>[];
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) continue;
      alerts.add(
        _RiskAlert(
          severity: _asString(m['severity']) ?? 'medium',
          message: _asString(m['message']) ?? '',
          share: _asDouble(m['share']),
          subject:
              _asString(m['symbol']) ??
              _asString(m['industry']) ??
              _asString(m['asset_id']) ??
              '',
        ),
      );
    }
    if (alerts.isEmpty) return const SizedBox.shrink();
    final visible = alerts.take(_kMaxVisibleRows).toList();
    final hidden = alerts.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in visible) _alertTile(context, a),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.s4,
              left: AppSpacing.s8,
            ),
            child: Text(
              l10n.aiToolHiddenItems(hidden),
              style: context.captionStyle,
            ),
          ),
      ],
    );
  }

  Widget _alertTile(BuildContext context, _RiskAlert alert) {
    final semantic = SemanticColors.of(context);
    final (bg, fg, icon) = switch (alert.severity) {
      'high' => (
        semantic.dangerContainer,
        semantic.onDangerContainer,
        FLucideIcons.circleAlert,
      ),
      'low' => (
        semantic.infoContainer,
        semantic.onInfoContainer,
        FLucideIcons.info,
      ),
      _ => (
        semantic.warningContainer,
        semantic.onWarningContainer,
        FLucideIcons.triangleAlert,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s4),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppIconSizes.sm, color: fg),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.subject.isEmpty
                      ? AppLocalizations.of(context).aiToolRiskAlertTitle
                      : alert.subject,
                  style: context.theme.typography.body.xs2.copyWith(color: fg),
                ),
                Text(
                  alert.message,
                  style: context.captionStyle.copyWith(color: fg),
                ),
              ],
            ),
          ),
          if (alert.share != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.s8),
              child: Text(
                NumberFormat.percentPattern().format(
                  alert.share!.clamp(0.0, 1.0),
                ),
                style: context.theme.typography.body.xs2.copyWith(
                  color: fg,
                  fontFeatures: TypographyTokens.tabularFigures,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RiskAlert {
  const _RiskAlert({
    required this.severity,
    required this.message,
    required this.share,
    required this.subject,
  });
  final String severity;
  final String message;
  final double? share;
  final String subject;
}
