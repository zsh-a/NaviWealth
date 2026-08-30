import 'package:flutter/widgets.dart';

import '../../../../design_system/design_system.dart';

/// Parses the raw comma/space separated tag field into canonical tags.
///
/// This matches the split every Knowledge save path applies, so the chip
/// preview never drifts from what is actually persisted.
List<String> parseKnowledgeTags(String raw) => raw
    .split(RegExp(r'[,，\s]+'))
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toSet()
    .toList(growable: false);

/// Outlined chip flow for a list of Knowledge tags.
class KnowledgeTagChips extends StatelessWidget {
  const KnowledgeTagChips({
    super.key,
    required this.tags,
    this.keyPrefix = 'knowledge-tag',
  });

  final List<String> tags;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        for (final tag in tags)
          AppBadge(
            key: ValueKey<String>('$keyPrefix-$tag'),
            label: tag,
            size: AppBadgeSize.compact,
            outlined: true,
          ),
      ],
    );
  }
}
