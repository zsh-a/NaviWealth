/// Editorial identity row for the HealthOS Today brief.
///
/// Replaces the static "Today" page title with a personalized greeting +
/// a concise briefing subtitle, matching the FinanceOS Today cockpit
/// (`home_greeting_header.dart`). The recovery hero below owns the domain
/// metrics; this row stays a stable page identity and hosts the headerless
/// shell chrome ([ShellActionRow]) plus the record-body-metric action that
/// previously lived in the `FHeader`.
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
      // No horizontal inset: `BriefScaffold` already applies the page
      // padding, so an inner one would push the greeting past the cards'
      // left edge.
      padding: const EdgeInsets.only(
        top: AppSpacing.s8,
        bottom: AppSpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _greeting(l10n, DateTime.now().hour),
                  style: context.briefGreetingTitleStyle,
                ),
              ),
              if (dataReady)
                AppIconButton(
                  icon: FLucideIcons.scale,
                  tooltip: l10n.healthRecordBodyMetricAction,
                  onPress: () => _recordBodyMetric(context, ref),
                ),
              // Headerless Today root: the greeting row is where the
              // cross-domain shell chrome lands (domain switch + global
              // Search / Settings). Hidden on desktop, where the dock /
              // sidebar own these.
              const ShellActionRow(),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(l10n.healthTodayBriefSubtitle, style: context.captionStyle),
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

  String _greeting(AppLocalizations l10n, int hour) {
    if (hour < 5) return l10n.homeGreetingNight;
    if (hour < 12) return l10n.homeGreetingMorning;
    if (hour < 18) return l10n.homeGreetingAfternoon;
    return l10n.homeGreetingEvening;
  }
}
