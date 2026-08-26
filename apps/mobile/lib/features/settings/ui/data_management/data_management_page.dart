import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_state.dart';
import '../../../../core/auth/domain_scope.dart';
import '../../../../core/auth/providers.dart' as auth_providers;
import '../../../../core/data_management/data_management.dart';
import '../../../../core/data_management/providers.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data_management/data_reset_coordinator.dart';

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  final Set<DomainScope> _clearing = <DomainScope>{};
  final Set<DomainScope> _resetting = <DomainScope>{};
  bool _maintenanceRunning = false;
  bool _sharedClearing = false;
  bool _compacting = false;
  bool _resettingAll = false;

  void _invalidateSnapshots() {
    ref.invalidate(domainDataSnapshotsProvider);
    ref.invalidate(sharedDataSnapshotProvider);
  }

  Future<void> _clearCache(DomainDataSnapshot snapshot) async {
    if (_clearing.contains(snapshot.scope) || snapshot.cacheRows == 0) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.dataManagementClearCacheConfirmTitle(snapshot.label)),
      body: Text(l10n.dataManagementClearCacheConfirmBody(snapshot.cacheRows)),
      confirmLabel: l10n.dataManagementClearCacheAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing.add(snapshot.scope));
    try {
      final service = await ref.read(dataManagementServiceProvider.future);
      final deleted = await service.clearCache(snapshot.scope);
      _invalidateSnapshots();
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.dataManagementClearCacheSuccess(deleted),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'data_management.clear_cache',
        ),
      );
    } finally {
      if (mounted) setState(() => _clearing.remove(snapshot.scope));
    }
  }

  Future<void> _setAutomaticMaintenance(bool enabled) async {
    final service = await ref.read(dataMaintenanceServiceProvider.future);
    await service.setAutomaticEnabled(enabled);
    ref.invalidate(automaticMaintenanceEnabledProvider);
  }

  Future<void> _runMaintenance() async {
    if (_maintenanceRunning) return;
    setState(() => _maintenanceRunning = true);
    try {
      final service = await ref.read(dataMaintenanceServiceProvider.future);
      final run = await service.runRetention();
      ref.invalidate(latestDataMaintenanceRunProvider);
      _invalidateSnapshots();
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(
          context,
        ).dataManagementMaintenanceSuccess(run.rowsAffected),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'data_management.run_maintenance',
        ),
      );
    } finally {
      if (mounted) setState(() => _maintenanceRunning = false);
    }
  }

  Future<void> _resetDomain(
    DomainDataSnapshot snapshot, {
    required bool everywhere,
  }) async {
    if (_resetting.contains(snapshot.scope)) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(
        everywhere
            ? l10n.dataManagementResetEverywhereConfirmTitle(snapshot.label)
            : l10n.dataManagementResetDeviceConfirmTitle(snapshot.label),
      ),
      body: Text(
        everywhere
            ? l10n.dataManagementResetEverywhereConfirmBody
            : l10n.dataManagementResetDeviceConfirmBody,
      ),
      confirmLabel: everywhere
          ? l10n.dataManagementResetEverywhereAction
          : l10n.dataManagementResetDeviceAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: everywhere ? FLucideIcons.cloudOff : FLucideIcons.smartphone,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting.add(snapshot.scope));
    try {
      final coordinator = await ref.read(dataResetCoordinatorProvider.future);
      final int affected;
      if (everywhere) {
        affected = (await coordinator.resetEverywhere(snapshot.scope)).affected;
      } else {
        affected = await coordinator.resetCurrentDevice(snapshot.scope);
      }
      _invalidateSnapshots();
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.dataManagementResetSuccess(affected),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'data_management.reset_domain',
        ),
      );
    } finally {
      if (mounted) setState(() => _resetting.remove(snapshot.scope));
    }
  }

  Future<void> _clearSharedHistory(SharedDataSnapshot snapshot) async {
    if (_sharedClearing || snapshot.historyRows == 0) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.dataManagementClearSharedConfirmTitle),
      body: Text(
        l10n.dataManagementClearSharedConfirmBody(snapshot.historyRows),
      ),
      confirmLabel: l10n.dataManagementClearSharedAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.brainCircuit,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sharedClearing = true);
    try {
      final service = await ref.read(dataManagementServiceProvider.future);
      final affected = await service.clearSharedHistory();
      _invalidateSnapshots();
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.dataManagementClearSharedSuccess(affected),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'data_management.clear_shared_history',
        ),
      );
    } finally {
      if (mounted) setState(() => _sharedClearing = false);
    }
  }

  Future<void> _compactDatabase() async {
    if (_compacting) return;
    setState(() => _compacting = true);
    try {
      final service = await ref.read(dataManagementServiceProvider.future);
      await service.compactDatabase();
      ref.invalidate(sharedDataSnapshotProvider);
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).dataManagementCompactSuccess,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'data_management.compact_database',
        ),
      );
    } finally {
      if (mounted) setState(() => _compacting = false);
    }
  }

  Future<void> _resetAll({required bool everywhere}) async {
    if (_resettingAll || _resetting.isNotEmpty) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(
        everywhere
            ? l10n.dataManagementResetAllEverywhereConfirmTitle
            : l10n.dataManagementResetAllDeviceConfirmTitle,
      ),
      body: Text(
        everywhere
            ? l10n.dataManagementResetAllEverywhereConfirmBody
            : l10n.dataManagementResetAllDeviceConfirmBody,
      ),
      confirmLabel: everywhere
          ? l10n.dataManagementResetAllEverywhereAction
          : l10n.dataManagementResetAllDeviceAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: everywhere ? FLucideIcons.cloudOff : FLucideIcons.smartphone,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingAll = true);
    try {
      final coordinator = await ref.read(dataResetCoordinatorProvider.future);
      var affected = everywhere
          ? (await coordinator.resetAllEverywhere()).affected
          : await coordinator.resetAllCurrentDevice();
      final service = await ref.read(dataManagementServiceProvider.future);
      affected += await service.clearSharedHistory();
      _invalidateSnapshots();
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.dataManagementResetSuccess(affected),
      );
    } catch (error, stackTrace) {
      _invalidateSnapshots();
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'data_management.reset_all',
        ),
      );
    } finally {
      if (mounted) setState(() => _resettingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshots = ref.watch(domainDataSnapshotsProvider);
    final sharedSnapshot = ref.watch(sharedDataSnapshotProvider);
    final optIns = ref.watch(auth_providers.domainOptInsProvider).value;
    final cloudEnabled =
        ref.watch(auth_providers.authStateProvider) is AuthLoggedIn;
    final automaticMaintenance = ref.watch(automaticMaintenanceEnabledProvider);
    final latestMaintenance = ref.watch(latestDataMaintenanceRunProvider);

    return AppPageScaffold(
      title: l10n.settingsDataManagementTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: <Widget>[
          SettingsHintText(l10n.settingsDataManagementSubtitle),
          const SizedBox(height: AppSpacing.s12),
          AppGroupedSurface(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: <Widget>[
                InlineLinkRow(
                  icon: FLucideIcons.shieldCheck,
                  label: l10n.dataManagementBackupTitle,
                  subtitle: l10n.dataManagementBackupSubtitle,
                  onTap: () => context.goNamed(SettingsRouteNames.backup),
                ),
                const AppGradientDivider(),
                InlineSwitchRow(
                  icon: FLucideIcons.calendarClock,
                  label: l10n.dataManagementAutomaticTitle,
                  subtitle: l10n.dataManagementAutomaticSubtitle,
                  value: automaticMaintenance.value ?? true,
                  onChanged: automaticMaintenance.isLoading
                      ? (_) {}
                      : _setAutomaticMaintenance,
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.sparkles,
                  label: l10n.dataManagementRunMaintenanceTitle,
                  subtitle: latestMaintenance.value == null
                      ? l10n.dataManagementRunMaintenanceNever
                      : l10n.dataManagementRunMaintenanceLast(
                          latestMaintenance.value!.rowsAffected,
                        ),
                  trailingValue: _maintenanceRunning
                      ? l10n.dataManagementMaintenanceRunning
                      : null,
                  onTap: _runMaintenance,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppStatusBanner(
            kind: AppStatusKind.info,
            icon: FLucideIcons.info,
            message: l10n.dataManagementSafetyNotice,
          ),
          const SizedBox(height: AppSpacing.s12),
          sharedSnapshot.when(
            loading: () => const SkeletonCard(
              padding: EdgeInsets.all(AppSpacing.s16),
              child: SkeletonBox(width: double.infinity, height: 160),
            ),
            error: (error, stackTrace) => AppStatusBanner(
              kind: AppStatusKind.error,
              icon: FLucideIcons.triangleAlert,
              message: userSafeErrorMessage(
                context,
                error,
                stackTrace: stackTrace,
                operation: 'data_management.load_shared_snapshot',
              ),
            ),
            data: (snapshot) => _SharedDataCard(
              snapshot: snapshot,
              clearing: _sharedClearing,
              compacting: _compacting,
              onClear: () => _clearSharedHistory(snapshot),
              onCompact: _compactDatabase,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          snapshots.when(
            loading: () => const SkeletonCard(
              padding: EdgeInsets.all(AppSpacing.s16),
              child: SkeletonBox(width: double.infinity, height: 220),
            ),
            error: (error, stackTrace) => AppStatusBanner(
              kind: AppStatusKind.error,
              icon: FLucideIcons.triangleAlert,
              message: userSafeErrorMessage(
                context,
                error,
                stackTrace: stackTrace,
                operation: 'data_management.load_domain_snapshots',
              ),
            ),
            data: (items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var index = 0; index < items.length; index++) ...[
                  _DomainDataCard(
                    snapshot: items[index],
                    enabled:
                        optIns?.contains(items[index].scope) ??
                        items[index].scope == DomainScope.finance,
                    clearing: _clearing.contains(items[index].scope),
                    resetting: _resetting.contains(items[index].scope),
                    cloudEnabled: cloudEnabled,
                    actionsEnabled: !_resettingAll,
                    onClearCache: () => _clearCache(items[index]),
                    onResetDevice: () =>
                        _resetDomain(items[index], everywhere: false),
                    onResetEverywhere: () =>
                        _resetDomain(items[index], everywhere: true),
                  ),
                  if (index != items.length - 1)
                    const SizedBox(height: AppSpacing.s12),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _GlobalResetCard(
            cloudEnabled: cloudEnabled,
            resetting: _resettingAll,
            actionsEnabled: _resetting.isEmpty,
            onResetDevice: () => _resetAll(everywhere: false),
            onResetEverywhere: () => _resetAll(everywhere: true),
          ),
        ],
      ),
    );
  }
}

class _SharedDataCard extends StatelessWidget {
  const _SharedDataCard({
    required this.snapshot,
    required this.clearing,
    required this.compacting,
    required this.onClear,
    required this.onCompact,
  });

  final SharedDataSnapshot snapshot;
  final bool clearing;
  final bool compacting;
  final Future<void> Function() onClear;
  final Future<void> Function() onCompact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                FLucideIcons.brainCircuit,
                size: AppIconSizes.sm,
                color: context.theme.colors.primary,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(
                  l10n.dataManagementSharedTitle,
                  style: context.titleLabelStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.dataManagementSharedSubtitle,
            style: context.bodyCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: _DataMetric(
                  value: snapshot.chatRows,
                  label: l10n.dataManagementChatRows,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: _DataMetric(
                  value: snapshot.aiRows,
                  label: l10n.dataManagementAiRows,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: _DataMetric(
                  value: snapshot.memoryRows,
                  label: l10n.dataManagementMemoryRows,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: _DataMetric(
                  value: snapshot.agentRows,
                  label: l10n.dataManagementAgentRows,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            l10n.dataManagementStorageUsage(
              _formatBytes(snapshot.databaseBytes),
              _formatBytes(snapshot.reclaimableBytes),
            ),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          const AppGradientDivider(),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: <Widget>[
              FButton(
                variant: FButtonVariant.outline,
                onPress: compacting ? null : () => onCompact(),
                child: Text(
                  compacting
                      ? l10n.dataManagementCompacting
                      : l10n.dataManagementCompactAction,
                ),
              ),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: clearing || snapshot.historyRows == 0
                    ? null
                    : () => onClear(),
                child: Text(
                  clearing
                      ? l10n.dataManagementClearing
                      : l10n.dataManagementClearSharedAction,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlobalResetCard extends StatelessWidget {
  const _GlobalResetCard({
    required this.cloudEnabled,
    required this.resetting,
    required this.actionsEnabled,
    required this.onResetDevice,
    required this.onResetEverywhere,
  });

  final bool cloudEnabled;
  final bool resetting;
  final bool actionsEnabled;
  final Future<void> Function() onResetDevice;
  final Future<void> Function() onResetEverywhere;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.dataManagementResetAllTitle,
            style: context.titleLabelStyle,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.dataManagementResetAllSubtitle,
            style: context.bodyCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: <Widget>[
              FButton(
                variant: FButtonVariant.outline,
                onPress: resetting || !actionsEnabled
                    ? null
                    : () => onResetDevice(),
                child: Text(l10n.dataManagementResetAllDeviceAction),
              ),
              if (cloudEnabled)
                FButton(
                  variant: FButtonVariant.destructive,
                  onPress: resetting || !actionsEnabled
                      ? null
                      : () => onResetEverywhere(),
                  child: Text(
                    resetting
                        ? l10n.dataManagementResetting
                        : l10n.dataManagementResetAllEverywhereAction,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DomainDataCard extends StatelessWidget {
  const _DomainDataCard({
    required this.snapshot,
    required this.enabled,
    required this.clearing,
    required this.resetting,
    required this.cloudEnabled,
    required this.actionsEnabled,
    required this.onClearCache,
    required this.onResetDevice,
    required this.onResetEverywhere,
  });

  final DomainDataSnapshot snapshot;
  final bool enabled;
  final bool clearing;
  final bool resetting;
  final bool cloudEnabled;
  final bool actionsEnabled;
  final Future<void> Function() onClearCache;
  final Future<void> Function() onResetDevice;
  final Future<void> Function() onResetEverywhere;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;

    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _domainIcon(snapshot.scope),
                size: AppIconSizes.sm,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(snapshot.label, style: context.titleLabelStyle),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: enabled
                      ? colors.primary.withValues(alpha: AppOpacity.whisper)
                      : colors.muted,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s4,
                  ),
                  child: Text(
                    enabled
                        ? l10n.dataManagementDomainEnabled
                        : l10n.dataManagementDomainDisabled,
                    style: context.captionLabelStyle.copyWith(
                      color: enabled ? colors.primary : colors.mutedForeground,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: _DataMetric(
                  value: snapshot.sourceRows,
                  label: l10n.dataManagementSourceRows,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: _DataMetric(
                  value: snapshot.deletedRows,
                  label: l10n.dataManagementDeletedRows,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: _DataMetric(
                  value: snapshot.cacheRows,
                  label: l10n.dataManagementCacheRows,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            l10n.dataManagementTableSummary(
              snapshot.sourceTableCount,
              snapshot.cacheTableCount,
            ),
            style: context.captionStyle,
          ),
          if (snapshot.cacheTableCount > 0) ...[
            const SizedBox(height: AppSpacing.s12),
            const AppGradientDivider(),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.dataManagementCacheHelp,
                    style: context.bodyCaptionStyle,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: snapshot.cacheRows == 0 || clearing
                      ? null
                      : () => onClearCache(),
                  child: Text(
                    clearing
                        ? l10n.dataManagementClearing
                        : l10n.dataManagementClearCacheAction,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          const AppGradientDivider(),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: <Widget>[
              FButton(
                variant: FButtonVariant.outline,
                onPress: resetting || !actionsEnabled
                    ? null
                    : () => context.goNamed(
                        SettingsRouteNames.backup,
                        queryParameters: <String, String>{
                          'domain': snapshot.scope.wire,
                        },
                      ),
                child: Text(l10n.dataManagementExportDomainAction),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: resetting || !actionsEnabled
                    ? null
                    : () => onResetDevice(),
                child: Text(l10n.dataManagementResetDeviceAction),
              ),
              if (cloudEnabled)
                FButton(
                  variant: FButtonVariant.destructive,
                  onPress: resetting || !actionsEnabled
                      ? null
                      : () => onResetEverywhere(),
                  child: Text(
                    resetting
                        ? l10n.dataManagementResetting
                        : l10n.dataManagementResetEverywhereAction,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataMetric extends StatelessWidget {
  const _DataMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.theme.colors.muted,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$value', style: context.titleLabelStyle),
          const SizedBox(height: AppSpacing.s2),
          Text(label, style: context.captionStyle, maxLines: 1),
        ],
      ),
    ),
  );
}

IconData _domainIcon(DomainScope scope) => switch (scope) {
  DomainScope.finance => FLucideIcons.walletCards,
  DomainScope.health => FLucideIcons.heartPulse,
  DomainScope.knowledge => FLucideIcons.brain,
  DomainScope.execution => FLucideIcons.listTodo,
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
  final mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(1)} MB';
  return '${(mib / 1024).toStringAsFixed(2)} GB';
}
