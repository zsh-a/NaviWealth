import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../tokens/dimens_tokens.dart';
import 'app_actions.dart';
import 'app_badge.dart';
import 'app_filter_chip.dart';
import 'app_interaction.dart';

/// Applied filters stay visible regardless of their picker presentation.
class AppFilterSummary extends StatelessWidget {
  const AppFilterSummary({
    super.key,
    required this.labels,
    required this.onClear,
    this.resultCount,
    this.onRemove,
  });

  final List<String> labels;
  final VoidCallback onClear;
  final int? resultCount;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.s6,
    runSpacing: AppSpacing.s6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (var index = 0; index < labels.length; index++)
        if (onRemove == null)
          AppBadge(label: labels[index], size: AppBadgeSize.compact)
        else
          AppFilterChip(
            label: labels[index],
            active: true,
            onPress: () => onRemove!(index),
            onClear: () => onRemove!(index),
            clearSemanticLabel:
                '${AppLocalizations.of(context).commonClearFilters}: ${labels[index]}',
          ),
      if (resultCount != null)
        Text(
          AppLocalizations.of(context).commonSearchResultsCount(resultCount!),
        ),
      AppActionButton(
        variant: FButtonVariant.ghost,
        mainAxisSize: MainAxisSize.min,
        hapticIntent: AppInteractionIntent.select,
        onPress: onClear,
        child: Text(AppLocalizations.of(context).commonClearFilters),
      ),
    ],
  );
}
