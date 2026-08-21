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
    final needsCollapse = widget.children.length > _kMetadataCollapseThreshold;
    final visibleChildren = needsCollapse && !_expanded
        ? widget.children.take(_kMetadataCollapseThreshold).toList()
        : widget.children;
    return KnowledgeSection.group(
      title: l10n.knowledgeDetailMetadataTitle,
      children: [
        AppMetadataStrip(children: visibleChildren),
        if (needsCollapse) ...[
          const SizedBox(height: AppSpacing.s4),
          AppRevealControl(
            expanded: _expanded,
            collapsedLabel: l10n.commonRevealMore(
              widget.children.length - _kMetadataCollapseThreshold,
            ),
            expandedLabel: l10n.commonRevealLess,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
        ],
      ],
    );
  }
}

/// Compact metadata pair on the parent surface.
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppMetadataItem(label: label, value: value);
  }
}

class _MetaTags extends StatelessWidget {
  const _MetaTags({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return AppMetadataTags(label: label, values: values);
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
            meta: decisionStatusLabelOf(
              AppLocalizations.of(context),
              decision.status,
            ),
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
            Padding(
              padding: const EdgeInsets.only(
                right: AppSpacing.s8,
                top: AppSpacing.s2,
              ),
              child: AppIconTile(
                icon: icon!,
                color: iconColor ?? colors.primary,
                size: AppIconSizes.lg,
                iconSize: 13,
                radius: AppRadius.sm,
                backgroundOpacity: AppOpacity.subtle,
                foregroundOpacity: 1,
              ),
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
    return press == null ? row : AppTappable(onPress: press, child: row);
  }
}
