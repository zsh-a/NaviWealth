part of 'dividend_center_page.dart';

class _ForecastCard extends ConsumerWidget {
  const _ForecastCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final forecast = ref.watch(dividendForecast12mProvider);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Icon(FLucideIcons.chartLine, color: context.theme.colors.primary),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: forecast.when(
              loading: () => const SkeletonBox(width: 180, height: 42),
              error: (error, stackTrace) => _ForecastText(
                title: l10n.dividendCenterForecastTitle,
                subtitle: l10n.dividendCenterForecastUnavailable,
              ),
              data: (projection) {
                final hasForecast = projection.total > Decimal.zero;
                final subtitle = hasForecast
                    ? l10n.dividendCenterForecastSource(
                        _strategyLabel(l10n, _dominantStrategy(projection)),
                      )
                    : l10n.dividendCenterForecastUnavailable;
                return _ForecastText(
                  title: l10n.dividendCenterForecastTitle,
                  value: hasForecast
                      ? formatters.currency(
                          projection.total,
                          code: projection.currency,
                        )
                      : null,
                  subtitle: subtitle,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastText extends StatelessWidget {
  const _ForecastText({
    required this.title,
    required this.subtitle,
    this.value,
  });

  final String title;
  final String subtitle;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.theme.typography.body.sm),
        if (value != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(value!, style: context.strongTitleStyle),
        ],
        const SizedBox(height: AppSpacing.s4),
        Text(subtitle, style: context.captionStyle),
      ],
    );
  }
}

String _dominantStrategy(ProjectedDividend projection) {
  if (projection.strategyBreakdown.isEmpty) return projection.strategy;
  return projection.strategyBreakdown.entries.reduce((a, b) {
    return a.value >= b.value ? a : b;
  }).key;
}

String _strategyLabel(AppLocalizations l10n, String strategy) {
  return switch (strategy) {
    'declared' => l10n.dividendForecastStrategyDeclared,
    'dps' => l10n.dividendForecastStrategyDps,
    'ttm' => l10n.dividendForecastStrategyTtm,
    'composite' => l10n.dividendForecastStrategyComposite,
    _ => l10n.dividendForecastStrategyUnknown,
  };
}
