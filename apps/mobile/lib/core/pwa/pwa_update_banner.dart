import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'pwa_update.dart';

/// Renders the app's child plus an inverted-surface banner overlay when
/// the service worker has a new version waiting. Only the web build can
/// ever show the banner — on mobile/desktop the underlying provider is a
/// no-op.
///
/// Wrap below `MaterialApp.router`'s builder so the banner inherits
/// `Localizations` and forui [FTheme] and can render above the route
/// content.
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
    final available = asyncAvailable.value ?? controller.isUpdateAvailableNow;
    final showBanner = available && !_dismissed;
    final l10n = AppLocalizations.of(context);

    final colors = context.theme.colors;
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.foreground,
                  boxShadow: AppShadow.banner,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s16,
                    vertical: AppSpacing.s12,
                  ),
                  child: Row(
                    children: [
                      Icon(FLucideIcons.download, color: colors.background),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: Text(
                          l10n.pwaUpdateAvailable,
                          style: context.theme.typography.sm.copyWith(
                            color: colors.background,
                          ),
                        ),
                      ),
                      FButton(
                        variant: FButtonVariant.ghost,
                        onPress: () => setState(() => _dismissed = true),
                        child: Text(l10n.pwaUpdateDismiss),
                      ),
                      const SizedBox(width: AppSpacing.s4),
                      FButton(
                        variant: FButtonVariant.outline,
                        onPress: controller.applyUpdate,
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
