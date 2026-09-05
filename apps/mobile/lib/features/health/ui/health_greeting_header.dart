/// Task heading and actions for the domain home.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'health_today_providers.dart';

class HealthGreetingHeader extends ConsumerWidget {
  const HealthGreetingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final dataReady = ref.watch(healthHasAnyDataProvider).value == true;

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.s8,
        bottom: AppSpacing.s16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              l10n.healthOverviewTitle,
              style: context.briefGreetingTitleStyle,
            ),
          ),
          if (dataReady)
            AppIconButton(
              icon: FLucideIcons.scale,
              tooltip: l10n.healthRecordBodyMetricAction,
              onPress: () => _recordBodyMetric(context, ref),
            ),
          const ShellActionRow(),
        ],
      ),
    );
  }

  Future<void> _recordBodyMetric(BuildContext context, WidgetRef ref) async {
    final saved = await showBodyMeasurementEntrySheet(
      context: context,
      initialKind: HealthMetricKind.weight,
    );
    if (saved == true) {
      ref.invalidate(healthTodaySnapshotProvider);
    }
  }
}
