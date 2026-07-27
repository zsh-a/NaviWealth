import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'biometric_auth_service.dart';
import 'biometric_lock_preferences.dart';

class BiometricLockGate extends ConsumerStatefulWidget {
  const BiometricLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends ConsumerState<BiometricLockGate>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(biometricUnlockSessionProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(biometricUnlockEnabledProvider);
    final unlocked = ref.watch(biometricUnlockSessionProvider);
    if (!enabled || unlocked) return widget.child;

    final availability = ref.watch(biometricAvailabilityProvider);
    return availability.when(
      data: (value) => switch (value) {
        BiometricAvailability.available => _LockedSurface(
          busy: _busy,
          onUnlock: _unlock,
        ),
        BiometricAvailability.notEnrolled ||
        BiometricAvailability.unsupported => widget.child,
      },
      loading: () => const _LockedSurface(busy: true),
      error: (_, _) => widget.child,
    );
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final ok = await ref
        .read(biometricAuthServiceProvider)
        .authenticate(reason: l10n.biometricUnlockReason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.read(biometricUnlockSessionProvider.notifier).unlock();
    } else {
      AppMessenger.show(context, ToastKind.error, l10n.biometricUnlockFailed);
    }
  }
}

class _LockedSurface extends StatelessWidget {
  const _LockedSurface({required this.busy, this.onUnlock});

  final bool busy;
  final FutureOr<void> Function()? onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: context.theme.colors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Breakpoints.compactContent,
            ),
            child: AppEmptyState(
              icon: FLucideIcons.fingerprint,
              title: l10n.biometricUnlockTitle,
              message: l10n.biometricUnlockSubtitle,
              action: FButton(
                onPress: busy || onUnlock == null
                    ? null
                    : () => unawaited(Future<void>.sync(onUnlock!)),
                child: Text(
                  busy
                      ? l10n.biometricUnlockChecking
                      : l10n.biometricUnlockButton,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
