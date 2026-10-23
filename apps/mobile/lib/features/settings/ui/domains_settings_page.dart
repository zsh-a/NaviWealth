import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/providers.dart' as auth_providers;
import '../../../core/lifeos/domain_pack.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Compact domain enablement and links to domain-owned configuration pages.
class DomainsSettingsPage extends ConsumerStatefulWidget {
  const DomainsSettingsPage({super.key});

  @override
  ConsumerState<DomainsSettingsPage> createState() =>
      _DomainsSettingsPageState();
}

class _DomainsSettingsPageState extends ConsumerState<DomainsSettingsPage> {
  DomainPack? _updating;
  ({DomainPack pack, bool enabled})? _failedChange;

  @override
  Widget build(BuildContext context) {
    final optIns = ref.watch(auth_providers.domainOptInsProvider);
    final l10n = AppLocalizations.of(context);
    final blocked =
        GoRouterState.of(context).uri.queryParameters['blocked'] != null;
    final packs = ref
        .watch(domainPackRegistryProvider)
        .where((pack) => pack.shell.settingsSpec != null);

    return AppPageScaffold(
      title: l10n.settingsDomainsTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          if (blocked) ...[
            AppStatusBanner(
              kind: AppStatusKind.info,
              message: l10n.settingsDomainsDeepLinkBlockedNotice,
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
          if (optIns.hasError) ...[
            AppStatusBanner(
              kind: AppStatusKind.error,
              message: l10n.commonLoadFailed,
              action: AppQuietButton(
                label: l10n.commonRetry,
                onPress: () =>
                    ref.invalidate(auth_providers.domainOptInsProvider),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
          if (_failedChange case final failed?) ...[
            AppStatusBanner(
              kind: AppStatusKind.error,
              message: l10n.settingsDomainsUpdateFailed(
                failed.pack.shell.settingsSpec!.label,
              ),
              action: AppQuietButton(
                label: l10n.commonRetry,
                onPress: _updating == null
                    ? () => _setDomainEnabled(failed.pack, failed.enabled)
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
          for (final (index, pack) in packs.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.s16),
            _DomainSettingsCard(
              spec: pack.shell.settingsSpec!,
              value:
                  pack.shell.settingsSpec!.alwaysEnabled ||
                  (optIns.value?.contains(pack.scope) ?? false),
              enabled: _updating == null && optIns.hasValue && !optIns.hasError,
              busy: _updating == pack,
              onChanged: (value) => _setDomainEnabled(pack, value),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setDomainEnabled(DomainPack pack, bool enabled) async {
    if (_updating != null) return;
    final l10n = AppLocalizations.of(context);
    final spec = pack.shell.settingsSpec!;
    if (!enabled) {
      final confirmed = await showConfirmDialog(
        context: context,
        title: Text(l10n.settingsDomainsDisableConfirmTitle(spec.label)),
        body: Text(l10n.settingsDomainsDisableConfirmBody(spec.label)),
        cancelLabel: l10n.commonCancel,
        confirmLabel: l10n.settingsDomainsDisableConfirmAction,
        destructive: true,
        icon: FLucideIcons.power,
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _updating = pack;
      _failedChange = null;
    });
    try {
      await ref
          .read(auth_providers.domainOptInsProvider.notifier)
          .setEnabled(pack.scope, enabled);
    } catch (error, stackTrace) {
      AppLogger.instance.e(
        'Domain enablement update failed (${pack.scope.wire})',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _failedChange = (pack: pack, enabled: enabled));
      }
      return;
    } finally {
      if (mounted) setState(() => _updating = null);
    }
    if (!mounted) return;
    if (enabled) {
      final resume = GoRouterState.of(context).uri.queryParameters['resume'];
      if (resume == pack.scope.wire && context.canPop()) {
        context.pop();
        return;
      }
      final homePath = pack.shell.navigation?.tabPaths.firstOrNull;
      if (homePath == null) return;
      final openNow = await showConfirmDialog(
        context: context,
        title: Text(l10n.settingsDomainsEnableSuccessTitle(spec.label)),
        body: Text(l10n.settingsDomainsEnableSuccessBody(spec.label)),
        cancelLabel: l10n.settingsDomainsOpenLater,
        confirmLabel: l10n.settingsDomainsOpenNow,
        icon: spec.icon,
      );
      if (openNow == true && mounted) context.go(homePath);
      return;
    }
    context.go(SettingsRoutes.domains);
    AppMessenger.show(
      context,
      ToastKind.info,
      l10n.settingsDomainsDisabledToast(spec.label),
    );
  }
}

class _DomainSettingsCard extends StatelessWidget {
  const _DomainSettingsCard({
    required this.spec,
    required this.value,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final DomainSettingsSpec spec;
  final bool value;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subtitle = busy ? l10n.commonSaving : spec.subtitle(l10n, value);
    return AppGroupedSurface(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        children: [
          if (spec.alwaysEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s14,
                vertical: AppSpacing.s10,
              ),
              child: Row(
                children: [
                  SettingsIconChip(icon: spec.icon),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Text(
                      spec.label,
                      style: context.theme.typography.body.sm,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  AppBadge(
                    label: l10n.settingsDomainsAlwaysOn,
                    size: AppBadgeSize.compact,
                  ),
                ],
              ),
            )
          else
            InlineSwitchRow(
              icon: spec.icon,
              label: spec.label,
              subtitle: subtitle,
              value: value,
              enabled: enabled,
              onChanged: onChanged,
            ),
          if (value && spec.detailPath != null) ...[
            const AppGroupedDivider(),
            InlineLinkRow(
              icon: FLucideIcons.slidersHorizontal,
              label: l10n.settingsDomainsConfigure(spec.label),
              onTap: () => context.push(spec.detailPath!),
            ),
          ],
        ],
      ),
    );
  }
}
