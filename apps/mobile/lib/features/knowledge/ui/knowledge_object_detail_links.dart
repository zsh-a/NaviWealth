part of 'knowledge_object_detail_page.dart';

const int _kMetadataCollapseThreshold = 4;

class _MetadataSection extends StatefulWidget {
  const _MetadataSection({required this.children});

  final List<Widget> children;

  @override
  State<_MetadataSection> createState() => _MetadataSectionState();
}

class _MetadataSectionState extends State<_MetadataSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final needsCollapse = widget.children.length > _kMetadataCollapseThreshold;
    final visibleChildren = needsCollapse && !_expanded
        ? widget.children.take(_kMetadataCollapseThreshold).toList()
        : widget.children;
    return KnowledgeSection.group(
      title: l10n.knowledgeDetailMetadataTitle,
      children: [
        Wrap(
          spacing: AppSpacing.s6,
          runSpacing: AppSpacing.s6,
          children: visibleChildren,
        ),
        if (needsCollapse) ...[
          const SizedBox(height: AppSpacing.s4),
          Center(
            child: FTappable(
              onPress: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: AnimatedRotation(
                  duration: motionDuration(context, Motion.fast),
                  turns: _expanded ? 0.5 : 0,
                  child: Icon(
                    FLucideIcons.chevronDown,
                    size: AppIconSizes.sm,
                    color: colors.mutedForeground,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact metadata chip. Borderless, muted fill — scannable without
/// visual weight.
class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            value,
            style: context.mediumLabelStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DecisionLinksSection extends StatelessWidget {
  const _DecisionLinksSection({required this.decisions});

  final List<KnowledgeDecision> decisions;

  @override
  Widget build(BuildContext context) {
    return KnowledgeSection.group(
      title: AppLocalizations.of(context).knowledgeDetailDecisionsTitle,
      children: [
        for (final decision in decisions)
          _RelatedObjectLink(
            label: decision.question,
            meta: decision.status.wire,
            icon: FLucideIcons.gitBranch,
            iconColor: context.theme.colors.primary,
            onPress: () => context.pushNamed(
              KnowledgeRouteNames.decisionDetail,
              pathParameters: {'id': decision.id},
            ),
          ),
      ],
    );
  }
}

class _RelatedObjectLink extends StatelessWidget {
  const _RelatedObjectLink({
    required this.label,
    required this.meta,
    this.onPress,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String meta;
  final VoidCallback? onPress;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: AppIconSizes.lg,
              height: AppIconSizes.lg,
              margin: const EdgeInsets.only(
                right: AppSpacing.s8,
                top: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: (iconColor ?? colors.primary).withValues(
                  alpha: AppOpacity.subtle,
                ),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Icon(icon, size: 13, color: iconColor ?? colors.primary),
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: typography.body.sm,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    meta,
                    style: context.captionStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onPress != null) ...[
            const SizedBox(width: AppSpacing.s8),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.xs,
              color: colors.mutedForeground.withValues(alpha: AppOpacity.muted),
            ),
          ],
        ],
      ),
    );
    final press = onPress;
    return press == null ? row : FTappable(onPress: press, child: row);
  }
}
