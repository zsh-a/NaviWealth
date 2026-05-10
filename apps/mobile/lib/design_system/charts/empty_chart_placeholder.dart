import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../theme/semantic_colors.dart';
import '../tokens/typography_tokens.dart';

/// Standard empty-state for any chart. Used by [Nw*Chart] when the data is
/// empty so business code never has to write its own if/else.
class EmptyChartPlaceholder extends StatelessWidget {
  const EmptyChartPlaceholder({
    super.key,
    this.message,
    this.icon = Icons.show_chart,
  });

  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = SemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: semantic.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: scheme.onSurfaceVariant, size: 32),
              const SizedBox(height: 8),
              Text(
                message ?? l10n.chartEmptyDefault,
                style: TypographyTokens.bodyMedium.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
