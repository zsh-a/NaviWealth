import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/auth/auth_api_client.dart';
import '../../../core/auth/auth_errors.dart';
import '../../../core/auth/providers.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/auth_controller.dart';

/// Loads the list of active sessions for the logged-in user. The provider
/// is family-less because there's only ever one logged-in user at a time;
/// `ref.invalidateSelf` after a logout-other-device action gets us a fresh
/// list without rebuilding the page widget.
class DevicesNotifier extends AsyncNotifier<DevicesResponse> {
  @override
  Future<DevicesResponse> build() async {
    final auth = ref.watch(authControllerProvider);
    final session = switch (auth.value) {
      AuthLoggedIn(:final session) => session,
      _ => null,
    };
    if (session == null) {
      // The router guard would normally prevent reaching this page in
      // logged-out state. Fail loud rather than show a confusing empty
      // list — the AsyncError surfaces in UI as the retry view.
      throw AuthException(AuthErrorKind.unauthorized);
    }
    final api = ref.read(authApiClientProvider);
    return api.listDevices(session);
  }

  Future<void> revoke(String deviceId) async {
    final session = ref.read(authControllerProvider.notifier).currentSession();
    if (session == null) return;
    final api = ref.read(authApiClientProvider);
    await api.logoutDevice(session, deviceId);
    if (deviceId == session.deviceId) {
      // Revoking ourselves — drop the local session immediately so the
      // router redirects to /login rather than letting the next request
      // 401 in-flight.
      await ref.read(authControllerProvider.notifier).logoutCurrent();
      return;
    }
    ref.invalidateSelf();
    await future;
  }
}

final devicesProvider = AsyncNotifierProvider<DevicesNotifier, DevicesResponse>(
  DevicesNotifier.new,
);

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(devicesProvider);
    return AppPageScaffold(
      title: l10n.authDevicesTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.refreshCw),
          onPress: () => ref.invalidate(devicesProvider),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.logOut),
          onPress: () => _confirmLogoutCurrent(context, ref),
        ),
      ],
      childPad: false,
      child: state.when(
        data: (data) => _DevicesList(response: data),
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => _ErrorView(
          message: l10n.authDevicesLoadError,
          details: error is AuthException ? error.message : '$error',
          onRetry: () => ref.invalidate(devicesProvider),
        ),
      ),
    );
  }

  Future<void> _confirmLogoutCurrent(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmDialog(
      context: context,
      title: Text(l10n.authLogoutDialogTitle),
      body: Text(l10n.authLogoutDialogBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.authLogoutDialogConfirm,
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).logoutCurrent();
  }
}

class _DevicesList extends ConsumerWidget {
  const _DevicesList({required this.response});

  final DevicesResponse response;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final devices = [...response.devices]
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      itemCount: devices.length,
      separatorBuilder: (_, _) => const FDivider(),
      itemBuilder: (context, i) {
        final device = devices[i];
        final isCurrent = device.id == response.currentDeviceId;
        return FTile(
          title: Text(
            device.name?.isNotEmpty == true
                ? device.name!
                : l10n.authDeviceUnnamed,
          ),
          prefix: Icon(
            isCurrent ? FLucideIcons.badgeCheck : FLucideIcons.monitor,
          ),
          subtitle: Text(
            l10n.authDeviceLastSeen(
              formatters.dateTime(device.lastSeenAt.toLocal()),
            ),
          ),
          suffix: isCurrent
              ? FBadge(child: Text(l10n.authDeviceCurrent))
              : FTooltip(
                  tipBuilder: (_, _) => Text(l10n.authDeviceRevokeTooltip),
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: () => _confirmRevoke(context, ref, device),
                    child: const Icon(
                      FLucideIcons.logOut,
                      size: AppIconSizes.h18,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    AuthDevice device,
  ) async {
    final l10n = AppLocalizations.of(context);
    final fallback = l10n.authDeviceRevokeError;
    final ok = await showConfirmDialog(
      context: context,
      title: Text(l10n.authDeviceRevokeDialogTitle),
      body: Text(
        l10n.authDeviceRevokeDialogBody(
          device.name?.isNotEmpty == true
              ? device.name!
              : l10n.authDeviceUnnamed,
        ),
      ),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.authDeviceRevokeConfirm,
    );
    if (ok != true) return;
    try {
      await ref.read(devicesProvider.notifier).revoke(device.id);
    } on AuthException catch (e) {
      if (!context.mounted) return;
      AppMessenger.show(context, ToastKind.error, e.message ?? fallback);
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.details, this.onRetry});

  final String message;
  final String? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FLucideIcons.circleAlert,
            size: AppIconSizes.xxl,
            color: context.theme.colors.destructive,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(message, textAlign: TextAlign.center),
          if (details != null && details!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              details!,
              textAlign: TextAlign.center,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.s16),
            FButton(
              variant: FButtonVariant.outline,
              onPress: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ],
      ),
    );
  }
}
