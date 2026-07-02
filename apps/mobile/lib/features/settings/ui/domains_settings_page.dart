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
    final l10n = AppLocalizations.of(context);

    return AppPageScaffold(
      title: l10n.settingsDomainsTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          const FinanceDomainSettingsSection(),
          for (final spec in _kDomainToggleSpecs) ...[
            const SizedBox(height: AppSpacing.s16),
            _DomainToggleCard(
              icon: spec.icon,
              label: spec.label,
              subtitle: spec.subtitle(
                l10n,
                optIns?.contains(spec.scope) ?? false,
              ),
              value: optIns?.contains(spec.scope) ?? false,
              onChanged: (v) => _setDomainEnabled(context, ref, spec, v),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setDomainEnabled(
    BuildContext context,
    WidgetRef ref,
    _DomainToggleSpec spec,
    bool enabled,
  ) async {
    await ref
        .read(auth_providers.domainOptInsProvider.notifier)
        .setEnabled(spec.scope, enabled);
    if (!context.mounted || enabled) return;
    final l10n = AppLocalizations.of(context);
    context.go(AppRoutes.settingsDomains);
    AppMessenger.show(
      context,
      ToastKind.info,
      l10n.settingsDomainsDisabledToast(spec.label),
    );
  }
}

typedef _DomainToggleSubtitle =
    String Function(AppLocalizations l10n, bool enabled);

class _DomainToggleSpec {
  const _DomainToggleSpec({
    required this.scope,
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final DomainScope scope;
  final IconData icon;
  final String label;
  final _DomainToggleSubtitle subtitle;
}

const List<_DomainToggleSpec> _kDomainToggleSpecs = <_DomainToggleSpec>[
  _DomainToggleSpec(
    scope: DomainScope.health,
    icon: FLucideIcons.heartPulse,
    label: 'HealthOS',
    subtitle: _healthSubtitle,
  ),
  _DomainToggleSpec(
    scope: DomainScope.knowledge,
    icon: FLucideIcons.brain,
    label: 'KnowledgeOS',
    subtitle: _knowledgeSubtitle,
  ),
  _DomainToggleSpec(
    scope: DomainScope.execution,
    icon: FLucideIcons.listTodo,
    label: 'ExecutionOS',
    subtitle: _executionSubtitle,
  ),
];

String _healthSubtitle(AppLocalizations l10n, bool enabled) => enabled
    ? l10n.settingsDomainsHealthEnabledSubtitle
    : l10n.settingsDomainsHealthDisabledSubtitle;

String _knowledgeSubtitle(AppLocalizations l10n, bool enabled) => enabled
    ? l10n.settingsDomainsKnowledgeEnabledSubtitle
    : l10n.settingsDomainsKnowledgeDisabledSubtitle;

String _executionSubtitle(AppLocalizations l10n, bool enabled) => enabled
    ? l10n.settingsDomainsExecutionEnabledSubtitle
    : l10n.settingsDomainsExecutionDisabledSubtitle;

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
