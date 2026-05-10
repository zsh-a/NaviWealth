import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

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
    final colors = context.theme.colors;
    final accent = titleColor ?? colors.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TypographyTokens.sectionHeaderTitle(accent)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
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
