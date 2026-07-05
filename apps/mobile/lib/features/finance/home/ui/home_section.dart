import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/design_system/design_system.dart';

/// Shared section grammar for the home cockpit.
///
/// Home cards should read as one coherent dashboard: a quiet section label,
/// an optional text action, then one or more soft surfaces. Keeping this
/// local to the home feature avoids leaking page-specific layout rules into
/// the app-wide design system.
class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: title,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
        child,
      ],
    );
  }
}

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.s4,
        top: AppSpacing.s4,
        bottom: AppSpacing.s8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.mutedLabelStyle,
            ),
          ),
          if (actionLabel != null && onAction != null)
            FTappable(
              onPress: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s2,
                ),
                child: Text(
                  actionLabel,
                  style: context.captionLabelStyle.copyWith(
                    color: context.theme.colors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HomeSurface extends StatelessWidget {
  const HomeSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onPress,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onPress: onPress,
      padding: padding,
      borderRadius: AppRadius.xlg,
      borderless: true,
      level: SoftCardLevel.raised,
      child: child,
    );
  }
}

class HomeCardHeader extends StatelessWidget {
  const HomeCardHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TypographyTokens.titleMedium.copyWith(
              color: context.theme.colors.foreground,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
