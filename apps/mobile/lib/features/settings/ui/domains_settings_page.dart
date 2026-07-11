import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth_providers;
import '../../../core/lifeos/domain_pack.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

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
        children: _domainSettingSections(
          context: context,
          ref: ref,
          optIns: optIns,
          l10n: l10n,
        ),
      ),
    );
  }

  List<Widget> _domainSettingSections({
    required BuildContext context,
    required WidgetRef ref,
    required DomainOptIns? optIns,
    required AppLocalizations l10n,
  }) {
    final sections = <Widget>[];
    for (final pack in ref.watch(domainPackRegistryProvider)) {
      final spec = pack.settingsSpec;
      if (spec == null) continue;
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: AppSpacing.s16));
      }
      final sectionBuilder = spec.sectionBuilder;
      if (sectionBuilder != null) {
        sections.add(sectionBuilder());
        continue;
      }
      sections.add(
        _DomainToggleCard(
          icon: spec.icon,
          label: spec.label,
          subtitle: spec.subtitle(l10n, optIns?.contains(pack.scope) ?? false),
          value: optIns?.contains(pack.scope) ?? false,
          onChanged: (v) => _setDomainEnabled(context, ref, pack, v),
        ),
      );
    }
    return sections;
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
    return AppGroupedSurface(
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
