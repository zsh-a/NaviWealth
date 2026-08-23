import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';

/// Neutral section header used above grouped cards / lists.
///
/// Two legal rhythms (audit §2 — six ad-hoc padding overrides collapsed):
///
/// * default — page-level sections that own their horizontal inset;
/// * [SectionHeader.module] — sections inside an already-padded module
///   column (Today briefs, tab bodies).
///
/// [titleColor] remains available for the rare semantic section that needs
/// emphasis; interactive trailing actions should carry the accent by default.
/// [titleStyle] / [subtitleStyle] are escape hatches for quiet caption-style
/// labels (settings groups, picker sections) — [titleColor] still applies on
/// top of an explicit [titleStyle].
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.titleStyle,
    this.subtitleStyle,
    this.trailing,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      AppSpacing.s24,
      AppSpacing.s16,
      AppSpacing.s10,
    ),
  });

  /// Section header inside an already-padded module column.
  const SectionHeader.module({
    Key? key,
    required String title,
    String? subtitle,
    Color? titleColor,
    TextStyle? titleStyle,
    TextStyle? subtitleStyle,
    Widget? trailing,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) : this(
         key: key,
         title: title,
         subtitle: subtitle,
         titleColor: titleColor,
         titleStyle: titleStyle,
         subtitleStyle: subtitleStyle,
         trailing: trailing,
         crossAxisAlignment: crossAxisAlignment,
         padding: const EdgeInsets.only(
           left: AppSpacing.s4,
           top: AppSpacing.s8,
           bottom: AppSpacing.s10,
         ),
       );

  final String title;
  final String? subtitle;
  final Color? titleColor;

  /// Title style override; [titleColor] still applies when both are set.
  final TextStyle? titleStyle;

  /// Subtitle style override.
  final TextStyle? subtitleStyle;

  final EdgeInsetsGeometry padding;

  /// Optional trailing widget (e.g. an action button) placed to the right
  /// of the title row.
  final Widget? trailing;

  /// Vertical alignment between the title block and [trailing]. Defaults to
  /// centered; headers with a two-line title block and a compact action may
  /// prefer [CrossAxisAlignment.end].
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final explicitTitleStyle = titleStyle;
    final resolvedTitleStyle = explicitTitleStyle == null
        ? TypographyTokens.sectionHeaderTitle(titleColor ?? colors.foreground)
        : titleColor != null
        ? explicitTitleStyle.copyWith(color: titleColor)
        : explicitTitleStyle;
    final resolvedSubtitleStyle =
        subtitleStyle ??
        TypographyTokens.sectionHeaderSubtitle(colors.mutedForeground);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: resolvedTitleStyle),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(subtitle!, style: resolvedSubtitleStyle),
        ],
      ],
    );
    return Padding(
      padding: padding,
      child: trailing != null
          ? Row(
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Expanded(child: titleBlock),
                trailing!,
              ],
            )
          : titleBlock,
    );
  }
}
