part of '_widgets.dart';

/// SoftCard with optional title and a children column.
///
/// Use [KnowledgeSection.item] for dense list rows and
/// [KnowledgeSection.group] for section / summary cards — the named
/// constructors encode the dense / raised padding rule.
class KnowledgeSection extends StatelessWidget {
  const KnowledgeSection({
    super.key,
    this.title,
    this.titleStyle,
    required this.children,
    this.padding = AppPageRhythm.cardPadding,
    this.trailing,
    this.onPress,
    this.level = SoftCardLevel.raised,
  });

  /// Dense list-item card: flat, borderless, s12 padding.
  const KnowledgeSection.item({
    Key? key,
    String? title,
    List<Widget> children = const <Widget>[],
    Widget? trailing,
    VoidCallback? onPress,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: AppPageRhythm.densePadding,
         trailing: trailing,
         onPress: onPress,
         level: SoftCardLevel.flat,
       );

  /// Grouped section card: raised module, expects a title.
  const KnowledgeSection.group({
    Key? key,
    required String title,
    required List<Widget> children,
    Widget? trailing,
    VoidCallback? onPress,
    SoftCardLevel level = SoftCardLevel.raised,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: AppPageRhythm.cardPadding,
         trailing: trailing,
         onPress: onPress,
         level: level,
       );

  final String? title;
  final TextStyle? titleStyle;
  final List<Widget> children;
  final EdgeInsets padding;
  final Widget? trailing;
  final VoidCallback? onPress;
  final SoftCardLevel level;

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: title,
      titleStyle: titleStyle,
      padding: padding,
      trailing: trailing,
      onPress: onPress,
      level: level,
      borderless: level == SoftCardLevel.flat,
      children: children,
    );
  }
}

/// Compact single-row surface for KnowledgeOS prompt/assistant controls.
///
/// Keeps KnowledgeOS card chrome centralized while still allowing dense,
/// toolbar-like surfaces that do not fit the section title/body shape.
class KnowledgePromptSurface extends StatelessWidget {
  const KnowledgePromptSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SoftCard.raised(
      borderless: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s8,
        AppSpacing.s8,
        AppSpacing.s8,
      ),
      child: child,
    );
  }
}

/// Pill badge for status labels (Decision lifecycle, Experiment state, …).
class KnowledgeStatusLabel extends StatelessWidget {
  const KnowledgeStatusLabel({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppBadge(label: label, outlined: true);
  }
}

/// Shared detail-page hero for KnowledgeOS objects.
class KnowledgeObjectHeader extends StatelessWidget {
  const KnowledgeObjectHeader({
    super.key,
    required this.icon,
    required this.color,
    required this.typeLabel,
    required this.title,
    required this.updatedAt,
    this.status,
  });

  final IconData icon;
  final Color color;
  final String typeLabel;
  final String title;
  final DateTime updatedAt;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeSection(
      title: typeLabel,
      level: SoftCardLevel.hero,
      padding: AppPageRhythm.heroPadding,
      trailing: status == null ? null : KnowledgeStatusLabel(label: status!),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconTile(
              icon: icon,
              color: color,
              size: 40,
              iconSize: AppIconSizes.h18,
              backgroundOpacity: AppOpacity.medium,
              foregroundOpacity: 1,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.displayTitleStyle,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Text(
                    l10n.knowledgeDetailUpdatedAt(
                      knowledgeDate(context, updatedAt, long: true),
                    ),
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
