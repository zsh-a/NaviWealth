import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/providers.dart' as auth_providers;
import '../../../core/lifeos/domain_pack.dart';
import '../../../core/shell/settings_route_paths.dart';
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
          for (final pack in ref.watch(domainPackRegistryProvider))
            if (pack.settingsSpec case final spec?) ...[
              const SizedBox(height: AppSpacing.s16),
              _DomainToggleCard(
                icon: spec.icon,
                label: spec.label,
                subtitle: spec.subtitle(
                  l10n,
                  optIns?.contains(pack.scope) ?? false,
                ),
                value: optIns?.contains(pack.scope) ?? false,
                onChanged: (v) => _setDomainEnabled(context, ref, pack, v),
              ),
            ],
        ],
      ),
    );
  }

  Future<void> _setDomainEnabled(
    BuildContext context,
    WidgetRef ref,
    DomainPack pack,
    bool enabled,
  ) async {
    await ref
        .read(auth_providers.domainOptInsProvider.notifier)
        .setEnabled(pack.scope, enabled);
    if (!context.mounted || enabled) return;
    final l10n = AppLocalizations.of(context);
    final label = pack.settingsSpec?.label ?? pack.scope.wire;
    context.go(SettingsRoutes.domains);
    AppMessenger.show(
      context,
      ToastKind.info,
      l10n.settingsDomainsDisabledToast(label),
    );
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
