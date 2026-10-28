/// Task heading and actions for the domain home.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/health_series_providers.dart';
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'health_check_in_sheet.dart';
import 'health_today_providers.dart';

enum _HealthCapture { meal, checkIn, body }

class HealthGreetingHeader extends ConsumerWidget {
  const HealthGreetingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellPageHeading(
      title: l10n.healthOverviewTitle,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.healthRecordAction,
          onPress: () => _capture(context, ref),
          order: -10,
        ),
      ],
    );
  }

  Future<void> _capture(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final action = await showAppSheet<_HealthCapture>(
      context: context,
      title: l.healthRecordAction,
      builder: (sheetContext) => AppActionSheetList(
        children: [
          AppActionSheetTile(
            icon: FLucideIcons.utensils,
            title: l.healthMealRecord,
            onPress: () => Navigator.of(sheetContext).pop(_HealthCapture.meal),
          ),
          AppActionSheetTile(
            icon: FLucideIcons.notebookPen,
            title: l.healthCheckInRecord,
            onPress: () =>
                Navigator.of(sheetContext).pop(_HealthCapture.checkIn),
          ),
          AppActionSheetTile(
            icon: FLucideIcons.scale,
            title: l.healthRecordBodyMetricAction,
            onPress: () => Navigator.of(sheetContext).pop(_HealthCapture.body),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case _HealthCapture.meal:
        await context.push<void>(HealthRoutes.mealNew);
      case _HealthCapture.checkIn:
        await showHealthCheckInSheet(
          context: context,
          day: ref.read(healthCalendarDayProvider),
        );
      case _HealthCapture.body:
        await _recordBodyMetric(context, ref);
      case null:
        break;
    }
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
