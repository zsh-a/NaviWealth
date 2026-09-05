part of 'settings_overview.dart';

class _Section extends StatelessWidget {
  const _Section({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Quiet inset-grouped section label. Typography carries the
        // hierarchy; no decorative accent is needed beside every settings
        // group.
        if (title case final heading?)
          SectionHeader(
            title: heading,
            titleStyle: context.captionLabelStyle,
            titleColor: context.theme.colors.mutedForeground,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s20,
              AppSpacing.s4,
              AppSpacing.s8,
            ),
          ),
        AppGroupedSurface(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: child,
        ),
      ],
    );
  }
}
