import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_api_client.dart';
import '../../../core/auth/auth_errors.dart';
import '../../../core/auth/providers.dart';
import '../../../core/format/providers.dart';
import '../../../core/haptics/haptics.dart';
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

final devicesProvider =
    AsyncNotifierProvider<DevicesNotifier, DevicesResponse>(
      DevicesNotifier.new,
    );

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(devicesProvider);
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.authDevicesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.authLogoutCurrentTooltip,
            onPressed: () => _confirmLogoutCurrent(context, ref),
          ),
        ],
      ),
      body: state.when(
        data: (data) => _DevicesList(response: data),
        loading: () => const Center(child: CircularProgressIndicator()),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.authLogoutDialogTitle),
        content: Text(l10n.authLogoutDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.authLogoutDialogConfirm),
          ),
        ],
      ),
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
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(devicesProvider),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
        itemCount: devices.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final device = devices[i];
          final isCurrent = device.id == response.currentDeviceId;
          return ListTile(
            leading: Icon(
              isCurrent ? Icons.verified_user : Icons.devices_other,
            ),
            title: Text(
              device.name?.isNotEmpty == true
                  ? device.name!
                  : l10n.authDeviceUnnamed,
            ),
            subtitle: Text(
              l10n.authDeviceLastSeen(
                formatters.dateTime(device.lastSeenAt.toLocal()),
              ),
            ),
            trailing: isCurrent
                ? Chip(
                    label: Text(l10n.authDeviceCurrent),
                    visualDensity: VisualDensity.compact,
                  )
                : IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: l10n.authDeviceRevokeTooltip,
                    onPressed: () => _confirmRevoke(context, ref, device),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    AuthDevice device,
  ) async {
    final l10n = AppLocalizations.of(context);
    // Capture the messenger up-front so we don't reach for `context` after
    // the awaited revoke (use_build_context_synchronously).
    final messenger = ScaffoldMessenger.maybeOf(context);
    final fallback = l10n.authDeviceRevokeError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.authDeviceRevokeDialogTitle),
        content: Text(
          l10n.authDeviceRevokeDialogBody(
            device.name?.isNotEmpty == true
                ? device.name!
                : l10n.authDeviceUnnamed,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.authDeviceRevokeConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(devicesProvider.notifier).revoke(device.id);
    } on AuthException catch (e) {
      Haptics.error();
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message ?? fallback)),
      );
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.s24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
          const SizedBox(height: Spacing.s12),
          Text(message, textAlign: TextAlign.center),
          if (details != null && details!.isNotEmpty) ...[
            const SizedBox(height: Spacing.s4),
            Text(
              details!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: Spacing.s16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ],
      ),
    );
  }
}
