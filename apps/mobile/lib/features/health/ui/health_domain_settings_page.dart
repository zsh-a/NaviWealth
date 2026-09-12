/// HealthOS domain detail settings.
///
/// Shows HealthOS-specific operational controls: Today link, platform sync,
/// and source synchronization. Reached from the Settings overview's
/// HealthOS row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'garmin_sync_status_card.dart';
import 'health_source_attention.dart';
import 'health_sources_summary.dart';

class HealthDomainSettingsPage extends ConsumerWidget {
  const HealthDomainSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: 'HealthOS',
      childPad: false,
      child: SettingsPageFrame(
        children: <Widget>[
          const HealthSourceAttention(),
          Text(l10n.healthSettingsSourcesTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.healthSettingsSourcesHelp, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s8),
          const SoftCard.raised(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: HealthPlatformSourceRow(manage: true),
          ),
          const SizedBox(height: AppPageRhythm.row),
          const GarminSyncStatusCard(),
        ],
      ),
    );
  }
}
