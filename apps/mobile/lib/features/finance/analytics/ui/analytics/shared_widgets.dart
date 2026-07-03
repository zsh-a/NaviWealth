part of '../analytics_page.dart';

class _MetricReadout extends StatelessWidget {
  const _MetricReadout({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.microLabelStyle),
          const SizedBox(height: AppSpacing.s2),
          Text(value, style: context.theme.typography.body.sm),
        ],
      ),
    );
  }
}

class _RiskAndBenchmarkColumn extends StatelessWidget {
  const _RiskAndBenchmarkColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiskAlertPanel(),
        SizedBox(height: AppSpacing.s24),
        BenchmarkComparisonCard(),
      ],
    );
  }
}
