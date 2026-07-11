part of 'settings_overview.dart';

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: title),
        AppGroupedSurface(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: child,
        ),
      ],
    );
  }
}

/// Quiet inset-grouped section label. Typography carries the hierarchy; no
/// decorative accent is needed beside every settings group.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s20,
        AppSpacing.s4,
        AppSpacing.s8,
      ),
      child: Text(
        title,
        style: context.captionLabelStyle.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      ),
    );
  }
}
