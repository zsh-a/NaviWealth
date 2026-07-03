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
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: child,
        ),
      ],
    );
  }
}

/// iOS-style inset-grouped section header: small, all-caps, muted,
/// with a subtle left accent bar for visual anchoring.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s6,
      ),
      child: Row(
        children: [
          Container(
            width: 2,
            height: AppSpacing.s12,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: AppOpacity.highlight),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            title.toUpperCase(),
            style: context.microLabelStyle.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
