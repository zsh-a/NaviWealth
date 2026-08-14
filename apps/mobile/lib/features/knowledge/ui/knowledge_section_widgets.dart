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
      children: children,
    );
  }
}

/// Continuous long-form section used for user-authored KnowledgeOS content.
///
/// Metadata and tools remain framed modules; prose sits directly on the page
/// so multiple sections read as one document instead of a stack of cards.
class KnowledgeDocumentSection extends StatelessWidget {
  const KnowledgeDocumentSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: AppSpacing.accentBar,
                height: AppSpacing.s16,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TypographyTokens.titleLarge.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          child,
        ],
      ),
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

/// Flexible card surface for KnowledgeOS controls and visual nodes that do not
/// have the title/body structure of [KnowledgeSection]. Keeping the SoftCard
/// construction here prevents local surfaces from drifting in chrome.
class KnowledgeCardSurface extends StatelessWidget {
  const KnowledgeCardSurface({
    super.key,
    required this.child,
    this.level = SoftCardLevel.flat,
    this.padding = AppPageRhythm.densePadding,
  });

  final Widget child;
  final SoftCardLevel level;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SoftCard(level: level, padding: padding, child: child);
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

/// Compact loading placeholder for KnowledgeOS sections: three shimmer
/// lines that mirror the section body rhythm. Page-level loads use the
/// design-system [AppListPageSkeleton] instead.
class KnowledgeSectionSkeleton extends StatelessWidget {
  const KnowledgeSectionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 14, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 220, height: 14, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 160, height: 14, radius: AppRadius.sm),
        ],
      ),
    );
  }
}

/// Consistent selectable row for KnowledgeOS sheets.
class KnowledgeSelectableRow extends StatelessWidget {
  const KnowledgeSelectableRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onPress,
    this.detail,
    this.mode = KnowledgeSelectionMode.checkbox,
    this.enabled = true,
    this.maxLines = 3,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onPress;
  final KnowledgeSelectionMode mode;
  final bool enabled;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final control = switch (mode) {
      KnowledgeSelectionMode.checkbox => FCheckbox(
        value: selected,
        onChange: enabled ? (_) => onPress() : null,
      ),
      KnowledgeSelectionMode.radio => FRadio(
        value: selected,
        onChange: enabled ? (_) => onPress() : null,
        semanticsLabel: label,
      ),
    };
    return AppTappable(
      onPress: enabled ? onPress : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: control,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: enabled
                        ? typography.body.sm
                        : context.bodyCaptionStyle,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      detail!,
                      style: context.captionStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text with a lightweight query highlight for KnowledgeOS search results.
class KnowledgeHighlightedText extends StatelessWidget {
  const KnowledgeHighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final String query;
  final TextStyle style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final match = lower.indexOf(normalizedQuery, cursor);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(cursor), style: style));
        break;
      }
      if (match > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match), style: style));
      }
      final end = match + normalizedQuery.length;
      spans.add(
        TextSpan(
          text: text.substring(match, end),
          style: highlightStyle ?? style.merge(context.searchHighlightStyle),
        ),
      );
      cursor = end;
    }
    return RichText(
      text: TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
