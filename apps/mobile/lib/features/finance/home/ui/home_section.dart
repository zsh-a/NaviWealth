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
        SectionHeader(
          title: title,
          padding: const EdgeInsets.only(
            left: AppSpacing.s4,
            top: AppSpacing.s8,
            bottom: AppSpacing.s10,
          ),
          trailing: actionLabel != null && onAction != null
              ? FTappable(
                  onPress: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                      vertical: AppSpacing.s2,
                    ),
                    child: Text(
                      actionLabel!,
                      style: context.captionLabelStyle.copyWith(
                        color: context.theme.colors.primary,
                      ),
                    ),
                  ),
                )
              : null,
        ),
        child,
      ],
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
    return SoftCard.raised(
      onPress: onPress,
      padding: padding,
      borderless: true,
      child: child,
    );
  }
}
