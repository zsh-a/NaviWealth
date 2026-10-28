import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Both previews use the production theme and card, including accessibility.
class AppearanceStylePicker extends ConsumerWidget {
  const AppearanceStylePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(visualStyleProvider);
    final brightness = context.theme.colors.brightness;
    final highContrast = MediaQuery.highContrastOf(context);
    final accentSeed = ref.watch(accentSeedProvider);
    final marketMode = ref.watch(marketColorModeProvider);

    Widget option(AppVisualStyle style) {
      final label = style == AppVisualStyle.classic
          ? l10n.visualStyleClassic
          : l10n.visualStyleRefined;
      final theme = resolveAppTheme(
        ThemeInputs(
          brightness: brightness,
          marketMode: marketMode,
          highContrast: highContrast,
          accentSeed: accentSeed,
          visualStyle: style,
        ),
      );
      final isSelected = selected == style;
      return Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: FTappable(
          key: ValueKey('appearance-style.${style.name}'),
          onPress: () {
            AppInteraction.signal(AppInteractionIntent.select);
            ref.read(visualStyleProvider.notifier).set(style);
          },
          child: DecoratedBox(
            decoration: context.appTheme.visual.decoration(
              radius: BorderRadius.circular(AppRadius.lg),
              color: theme.surfaces.canvas,
              side: BorderSide(
                color: isSelected
                    ? context.theme.colors.primary
                    : context.theme.colors.border,
                width: isSelected ? AppStroke.branch : AppStroke.hairline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: AppThemeScope(
                      data: theme,
                      child: FTheme(
                        data: buildAppForuiTheme(
                          brightness: brightness,
                          touch: true,
                          highContrast: highContrast,
                          accentSeed: accentSeed,
                          visualStyle: style,
                        ),
                        child: SoftCard.raised(
                          padding: const EdgeInsets.all(AppSpacing.s12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.activityActionsTitle,
                                style: theme.type.title.copyWith(
                                  color: theme.content.strong,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s12),
                              Row(
                                children: [
                                  Icon(
                                    FLucideIcons.plus,
                                    size: AppIconSizes.sm,
                                    color: theme.accent.fg,
                                  ),
                                  const SizedBox(width: AppSpacing.s8),
                                  Expanded(
                                    child: Text(
                                      l10n.superFabExpense,
                                      style: theme.type.bodySmall.copyWith(
                                        color: theme.content.body,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Row(
                    children: [
                      Expanded(child: Text(label, style: context.labelStyle)),
                      if (isSelected)
                        Icon(
                          FLucideIcons.circleCheck,
                          size: AppIconSizes.sm,
                          color: context.theme.colors.primary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsVisualStyleTitle, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              if (stacked) {
                return Column(
                  children: [
                    option(AppVisualStyle.classic),
                    const SizedBox(height: AppSpacing.s12),
                    option(AppVisualStyle.refined),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: option(AppVisualStyle.classic)),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(child: option(AppVisualStyle.refined)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
