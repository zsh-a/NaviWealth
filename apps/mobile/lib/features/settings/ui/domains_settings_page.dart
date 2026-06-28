import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth_providers;
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'finance_domain_settings_section.dart';
import 'inline_setting_row.dart';
import 'settings_page_frame.dart';

/// `/settings/domains` — LifeOS domain management.
///
/// FinanceOS is always on; optional domains expose enablement here.
class DomainsSettingsPage extends ConsumerWidget {
  const DomainsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIns = ref.watch(auth_providers.domainOptInsProvider).value;
    final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
    final knowledgeEnabled = optIns?.contains(DomainScope.knowledge) ?? false;
    final executionEnabled = optIns?.contains(DomainScope.execution) ?? false;
    final l10n = AppLocalizations.of(context);

    return AppPageScaffold(
      title: l10n.settingsDomainsTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          const FinanceDomainSettingsSection(),
          const SizedBox(height: AppSpacing.s16),
          _DomainToggleCard(
            icon: FLucideIcons.heartPulse,
            label: 'HealthOS',
            subtitle: healthEnabled
                ? l10n.settingsDomainsHealthEnabledSubtitle
                : l10n.settingsDomainsHealthDisabledSubtitle,
            value: healthEnabled,
            onChanged: (v) =>
                _setDomainEnabled(context, ref, DomainScope.health, v),
          ),
          const SizedBox(height: AppSpacing.s16),
          _DomainToggleCard(
            icon: FLucideIcons.brain,
            label: 'KnowledgeOS',
            subtitle: knowledgeEnabled
                ? l10n.settingsDomainsKnowledgeEnabledSubtitle
                : l10n.settingsDomainsKnowledgeDisabledSubtitle,
            value: knowledgeEnabled,
            onChanged: (v) =>
                _setDomainEnabled(context, ref, DomainScope.knowledge, v),
          ),
          const SizedBox(height: AppSpacing.s16),
          _DomainToggleCard(
            icon: FLucideIcons.listTodo,
            label: 'ExecutionOS',
            subtitle: executionEnabled
                ? l10n.settingsDomainsExecutionEnabledSubtitle
                : l10n.settingsDomainsExecutionDisabledSubtitle,
            value: executionEnabled,
            onChanged: (v) =>
                _setDomainEnabled(context, ref, DomainScope.execution, v),
          ),
        ],
      ),
    );
  }

  Future<void> _setDomainEnabled(
    BuildContext context,
    WidgetRef ref,
    DomainScope scope,
    bool enabled,
  ) async {
    await ref
        .read(auth_providers.domainOptInsProvider.notifier)
        .setEnabled(scope, enabled);
    if (!context.mounted || enabled) return;
    final l10n = AppLocalizations.of(context);
    context.go(AppRoutes.settingsDomains);
    AppMessenger.show(
      context,
      ToastKind.info,
      l10n.settingsDomainsDisabledToast(_domainLabel(scope)),
    );
  }

  String _domainLabel(DomainScope scope) {
    return switch (scope) {
      DomainScope.finance => 'FinanceOS',
      DomainScope.health => 'HealthOS',
      DomainScope.knowledge => 'KnowledgeOS',
      DomainScope.execution => 'ExecutionOS',
    };
  }
}

class _DomainToggleCard extends StatelessWidget {
  const _DomainToggleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: InlineSwitchRow(
        icon: icon,
        label: label,
        subtitle: subtitle,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
