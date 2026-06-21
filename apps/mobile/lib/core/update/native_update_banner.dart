import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'native_update.dart';

/// Native iOS/Android counterpart to [PwaUpdateBanner].
///
/// The prompt is driven by release-channel dart-defines and is a no-op on
/// web/desktop. It intentionally opens the platform's external distribution
/// URL instead of trying to bypass App Store / Play Store ownership.
class NativeUpdateBanner extends ConsumerWidget {
  const NativeUpdateBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(nativeUpdateStateProvider);
    final state = asyncState.value;
    if (state == null || !state.shouldShow) {
      return child;
    }

    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Stack(
      children: [
        child,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(FLucideIcons.download, color: colors.background),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: Text(
                            l10n.nativeUpdateAvailable(state.latestVersion),
                            style: context.theme.typography.sm.copyWith(
                              color: colors.background,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s8,
                      children: [
                        if (!state.requiredUpdate)
                          FButton(
                            variant: FButtonVariant.ghost,
                            onPress: () => _dismiss(ref, state),
                            child: Text(l10n.nativeUpdateDismiss),
                          ),
                        FButton(
                          variant: FButtonVariant.outline,
                          onPress: () => _openUpdate(context, state.updateUrl),
                          child: Text(l10n.nativeUpdateApply),
                        ),
                      ],
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

  Future<void> _dismiss(WidgetRef ref, NativeUpdateState state) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(kNativeUpdateDismissedVersionKey, state.latestVersion);
    ref.invalidate(nativeUpdateStateProvider);
  }

  Future<void> _openUpdate(BuildContext context, String updateUrl) async {
    final uri = Uri.tryParse(updateUrl);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).nativeUpdateOpenFailed,
      );
    }
  }
}
