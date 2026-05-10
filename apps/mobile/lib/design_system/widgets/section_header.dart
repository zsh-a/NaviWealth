import 'package:flutter/material.dart';

import '../tokens/spacing_tokens.dart';
import '../tokens/typography_tokens.dart';

/// Accent-coloured section header used above grouped cards / lists.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
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
