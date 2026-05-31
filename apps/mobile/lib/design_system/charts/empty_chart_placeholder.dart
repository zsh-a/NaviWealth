import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';

/// Standard empty-state for any chart. Used by `Nw*Chart` when the data is
/// empty so business code never has to write its own if/else.
class EmptyChartPlaceholder extends StatelessWidget {
  const EmptyChartPlaceholder({
    super.key,
    this.message,
    this.icon = FLucideIcons.trendingUp,
  });

  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colors.mutedForeground, size: AppIconSizes.xl),
              const SizedBox(height: AppSpacing.s8),
              Text(
                message ?? l10n.chartEmptyDefault,
                style: TypographyTokens.bodyMedium.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
