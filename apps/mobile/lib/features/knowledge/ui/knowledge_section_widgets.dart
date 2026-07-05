part of '_widgets.dart';

/// SoftCard with optional title and a children column.
///
/// Use [KnowledgeSection.item] for dense list rows and
/// [KnowledgeSection.group] for section / summary cards — the named
/// constructors encode the s12 / s16 padding rule documented above.
/// The raw constructor exists for the rare case where a custom
/// padding really is needed.
class KnowledgeSection extends StatelessWidget {
  const KnowledgeSection({
    super.key,
    this.title,
    this.titleStyle,
    required this.children,
    this.padding = const EdgeInsets.all(AppSpacing.s16),
    this.trailing,
    this.onPress,
  });

  /// Dense list-item card: s12 padding, no header by convention
  /// (callers usually inline their own row layout).
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
         padding: const EdgeInsets.all(AppSpacing.s12),
         trailing: trailing,
         onPress: onPress,
       );

  /// Grouped section card: s16 padding, expects a title.
  const KnowledgeSection.group({
    Key? key,
    required String title,
    required List<Widget> children,
    Widget? trailing,
    VoidCallback? onPress,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: const EdgeInsets.all(AppSpacing.s16),
         trailing: trailing,
         onPress: onPress,
       );

  final String? title;
  final TextStyle? titleStyle;
  final List<Widget> children;
  final EdgeInsets padding;

  /// Optional trailing widget in the title row (e.g. a status badge).
  final Widget? trailing;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: title,
      titleStyle: titleStyle,
      padding: padding,
      trailing: trailing,
      onPress: onPress,
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
    return SoftCard(
      borderRadius: AppRadius.sm,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s10,
        AppSpacing.s6,
        AppSpacing.s6,
        AppSpacing.s6,
      ),
      child: child,
    );
  }
}

/// Pill badge for status labels (Decision lifecycle, Experiment state, …).
///
/// Replaces the two byte-identical `_StatusBadge` / `_Badge` definitions
/// that lived in `knowledge_library_page.dart` and
/// `knowledge_decision_detail_page.dart`.
class KnowledgeStatusLabel extends StatelessWidget {
  const KnowledgeStatusLabel({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppBadge(label: label, outlined: true);
  }
}

/// Shared detail-page hero for KnowledgeOS objects.
///
/// Keeps object identity consistent across Decision and non-Decision
/// detail pages: type label, type icon, title, status, and last update
/// timestamp are always in the same place.
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
    return KnowledgeSection.group(
      title: typeLabel,
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
                    style: context.strongTitleStyle,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s4),
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
