import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';

/// Standard content frame for settings sub-pages.
///
/// Keeps second-level settings screens aligned with the settings overview:
/// a centered readable column, consistent page padding, and safe-area aware
/// bottom spacing.
class SettingsPageFrame extends StatelessWidget {
  const SettingsPageFrame({
    super.key,
    required this.children,
    this.maxWidth = AdaptiveMaxWidth.narrow,
    this.topPadding = AppSpacing.s16,
    this.bottomPadding = AppSpacing.s24,
  });

  final List<Widget> children;
  final double maxWidth;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        AdaptiveContentFrame(
          maxWidth: maxWidth,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.s16,
            topPadding,
            AppSpacing.s16,
            bottomPadding + MediaQuery.paddingOf(context).bottom,
          ),
          primary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class SettingsHintText extends StatelessWidget {
  const SettingsHintText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      child: Text(text, style: context.captionStyle.copyWith(height: 1.45)),
    );
  }
}

class SettingsFooterAction extends StatelessWidget {
  const SettingsFooterAction({
    super.key,
    required this.label,
    required this.onPress,
    this.icon,
  });

  final String label;
  final VoidCallback onPress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s14,
        AppSpacing.s8,
        AppSpacing.s14,
        AppSpacing.s8,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FButton(
          variant: FButtonVariant.ghost,
          onPress: onPress,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIconSizes.xs),
                const SizedBox(width: AppSpacing.s6),
              ],
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
