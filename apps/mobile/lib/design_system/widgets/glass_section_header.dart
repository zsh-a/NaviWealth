import 'package:flutter/material.dart';

import '../tokens/spacing_tokens.dart';
import '../tokens/typography_tokens.dart';

/// Accent-colored section header (Apple News style).
///
/// Replaces the various `_SectionHeader` implementations across pages
/// with a single design-system widget. The title defaults to the theme's
/// primary color; pass [titleColor] to override (e.g. `ColorPalette.red500`
/// for a danger section).
class GlassSectionHeader extends StatelessWidget {
  const GlassSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = titleColor ?? theme.colorScheme.primary;
    return Padding(
      padding: Spacing.sectionHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TypographyTokens.sectionHeaderTitle(accent)),
          if (subtitle != null) ...[
            const SizedBox(height: Spacing.s4),
            Text(
              subtitle!,
              style: TypographyTokens.sectionHeaderSubtitle(
                theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
