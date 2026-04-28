import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import 'pwa_update.dart';

/// Renders the app's child plus a `MaterialBanner` overlay when the
/// service worker has a new version waiting. Only the web build can ever
/// show the banner — on mobile/desktop the underlying provider is a no-op.
///
/// Wrap below `MaterialApp.router`'s builder so the banner inherits
/// `Localizations` and `Theme` and can render above the route content.
class PwaUpdateBanner extends ConsumerStatefulWidget {
  const PwaUpdateBanner({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PwaUpdateBanner> createState() => _PwaUpdateBannerState();
}

class _PwaUpdateBannerState extends ConsumerState<PwaUpdateBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(pwaUpdateControllerProvider);
    if (!controller.isSupported) {
      return widget.child;
    }
    final asyncAvailable = ref.watch(pwaUpdateAvailableProvider);
    final available =
        asyncAvailable.valueOrNull ?? controller.isUpdateAvailableNow;
    final showBanner = available && !_dismissed;
    final l10n = AppLocalizations.of(context);

    return Stack(
      children: [
        widget.child,
        if (showBanner)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Material(
                elevation: 6,
                color: Theme.of(context).colorScheme.inverseSurface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.system_update_alt,
                        color: Theme.of(context).colorScheme.onInverseSurface,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.pwaUpdateAvailable,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onInverseSurface,
                              ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _dismissed = true),
                        child: Text(l10n.pwaUpdateDismiss),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.tonal(
                        onPressed: controller.applyUpdate,
                        child: Text(l10n.pwaUpdateApply),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
