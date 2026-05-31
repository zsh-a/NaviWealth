import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';

/// Accent-coloured section header used above grouped cards / lists.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Color? titleColor;

  /// Optional trailing widget (e.g. an action button) placed to the right
  /// of the title row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = titleColor ?? colors.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s20,
        AppSpacing.s16,
        AppSpacing.s8,
      ),
      child: trailing != null
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TypographyTokens.sectionHeaderTitle(accent),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          subtitle!,
                          style: TypographyTokens.sectionHeaderSubtitle(
                            colors.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing!,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TypographyTokens.sectionHeaderTitle(accent)),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    subtitle!,
                    style: TypographyTokens.sectionHeaderSubtitle(
                      colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
