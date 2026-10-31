import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'app_actions.dart';
import 'app_glass.dart';
import 'app_interaction.dart';
import 'app_selection_indicator.dart';

const double kFloatingGlassNavBarHeight = AppSpacing.s64;
const double _kIconSlotSize = 26;
const double _kAssistantLabelBreakpoint = 390;
const double _kNavLabelLineHeight = 1.15;

int _navigationLabelMaxLines(BuildContext context) {
  final size = TypographyTokens.labelSmall.fontSize!;
  return MediaQuery.textScalerOf(context).scale(size) > size * 1.5 ? 2 : 1;
}

/// Shared by the dock and shell reservation; enlarged labels keep their scale.
double floatingGlassNavBarHeight(BuildContext context) {
  final fontSize = TypographyTokens.labelSmall.fontSize!;
  final scaledSize = MediaQuery.textScalerOf(context).scale(fontSize);
  final extraHeight =
      ((scaledSize * _navigationLabelMaxLines(context) - fontSize) *
              _kNavLabelLineHeight)
          .clamp(0.0, double.infinity);
  return (kFloatingGlassNavBarHeight + extraHeight).ceilToDouble();
}

/// A floating glass-morphism bottom navigation bar.
///
/// Renders the page destinations in a translucent capsule, with an optional
/// independent assistant action at the trailing edge. Both share one height
/// and reveal lifecycle, so the action never reads as another page tab or
/// covers page-level floating actions.
///
/// The assistant uses an opaque accent tint rather than another live-blur
/// surface. Labels appear only when every destination retains enough room.
///
/// When [onAssistantAction] is null, no assistant button is rendered and tabs
/// fill the full width evenly.
class FloatingGlassNavBar extends StatelessWidget {
  const FloatingGlassNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onIndexChanged,
    this.onAssistantAction,
    this.assistantIcon = FLucideIcons.sparkles,
    this.assistantLabel,
    this.assistantSemanticLabel,
    this.accentColor,
  });

  /// Navigation destinations.
  final List<FloatingNavTab> items;

  /// Currently selected tab index (0-based, among [items]).
  final int selectedIndex;

  /// Called when a tab is tapped.
  final ValueChanged<int> onIndexChanged;

  /// Called when the trailing assistant action is tapped. When `null`, no
  /// assistant button is rendered.
  final VoidCallback? onAssistantAction;

  /// Icon for the assistant action button.
  final IconData assistantIcon;

  /// Short visible action label, e.g. `Ask AI` / `问 AI`.
  final String? assistantLabel;

  /// Full localized accessibility label for the assistant action.
  final String? assistantSemanticLabel;

  /// Optional selected-tab tint (e.g. a domain accent). Null keeps the
  /// global primary.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = floatingGlassNavBarHeight(context);
        final destinationHeight = height - AppSpacing.s12;
        final labeledAssistantWidth = onAssistantAction == null
            ? null
            : _labeledAssistantWidth(
                context,
                constraints.maxWidth,
                kFloatingGlassNavBarHeight,
              );
        return SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AppGlassSurface(
                  key: const ValueKey('floating-nav.destinations'),
                  // Keep live glass confined to the navigation capsule. The
                  // theme still supplies the opaque high-contrast fallback.
                  frosted: true,
                  softLight: true,
                  trackPointer: true,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadow.nav,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s6,
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavTabButton(
                            tab: items[i],
                            selected: i == selectedIndex,
                            height: destinationHeight,
                            accentColor: accentColor,
                            onTap: () => onIndexChanged(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (onAssistantAction != null) ...[
                const SizedBox(width: AppSpacing.s12),
                _AssistantActionButton(
                  icon: assistantIcon,
                  label: labeledAssistantWidth == null ? null : assistantLabel,
                  semanticLabel: assistantSemanticLabel,
                  width: labeledAssistantWidth ?? kFloatingGlassNavBarHeight,
                  height: kFloatingGlassNavBarHeight,
                  onTap: onAssistantAction!,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  double? _labeledAssistantWidth(
    BuildContext context,
    double availableWidth,
    double height,
  ) {
    final label = assistantLabel;
    if (label == null ||
        label.isEmpty ||
        availableWidth < _kAssistantLabelBreakpoint) {
      return null;
    }
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    try {
      double measure(String text, TextStyle style) {
        painter.text = TextSpan(text: text, style: style);
        painter.layout();
        return painter.width;
      }

      var tabWidth = AppControlHeights.touchTarget;
      for (final tab in items) {
        final width =
            measure(tab.label, TypographyTokens.labelSmall) + AppSpacing.s12;
        if (width > tabWidth) tabWidth = width;
      }
      final contentWidth =
          measure(label, TypographyTokens.labelSmallMedium) +
          AppIconSizes.md +
          AppSpacing.s6 +
          AppSpacing.s24;
      final actionWidth = contentWidth < height
          ? height
          : contentWidth.ceilToDouble();
      final requiredWidth =
          tabWidth * items.length +
          AppSpacing.s16 +
          AppSpacing.s12 +
          actionWidth;
      return requiredWidth <= availableWidth ? actionWidth : null;
    } finally {
      painter.dispose();
    }
  }
}

/// A single tab destination for [FloatingGlassNavBar].
class FloatingNavTab {
  const FloatingNavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

// ── Private widgets ───────────────────────────────────────────────────────

class _NavTabButton extends StatelessWidget {
  const _NavTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.height,
    this.accentColor,
  });

  final FloatingNavTab tab;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final selectedColor = accentColor ?? colors.primary;
    final selectedSurface = Color.alphaBlend(
      selectedColor.withValues(alpha: AppOpacity.softTint),
      colors.card,
    );
    final iconColor = selected ? selectedColor : colors.mutedForeground;
    final labelColor = selected ? selectedColor : colors.mutedForeground;
    return AppActionTappable(
      selected: selected,
      semanticsLabel: tab.label,
      focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      builder: (context, variants, child) => AppGlassFeedback(
        variants: variants,
        accentColor: accentColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          decoration: context.appTheme.visual.decoration(
            radius: BorderRadius.circular(AppRadius.md),
            // Fade only alpha. Transparent black also interpolates the RGB
            // channels and makes the outgoing destination briefly turn gray.
            color: selected
                ? selectedSurface
                : selectedSurface.withValues(alpha: AppOpacity.transparent),
          ),
          child: child,
        ),
      ),
      onPress: () {
        if (!selected) {
          AppInteraction.signal(AppInteractionIntent.navigate);
        }
        onTap();
      },
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: _kIconSlotSize,
                height: _kIconSlotSize,
                // Selection is signalled by the accent colour plus the
                // underline indicator below; the icon glyph stays fixed so
                // tabs do not need paired outline/filled assets.
                child: Center(
                  child: Icon(
                    tab.icon,
                    color: iconColor,
                    size: AppIconSizes.h18,
                  ),
                ),
              ),
              Text(
                tab.label,
                style:
                    (selected
                            ? TypographyTokens.labelSmall
                            : TypographyTokens.labelSmallMedium)
                        .copyWith(
                          color: labelColor,
                          height: _kNavLabelLineHeight,
                        ),
                maxLines: _navigationLabelMaxLines(context),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s2),
              AppSelectionIndicator(
                selected: selected,
                length: AppSpacing.s16,
                thickness: AppSpacing.s2,
                color: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantActionButton extends StatelessWidget {
  const _AssistantActionButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final IconData icon;
  final String? label;
  final String? semanticLabel;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = colors.primary;

    return AppActionTappable(
      semanticsLabel: semanticLabel ?? label ?? 'AI',
      onPress: onTap,
      focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      builder: (context, variants, child) {
        final tint = variants.contains(FTappableVariant.pressed)
            ? AppOpacity.highlight
            : variants.contains(FTappableVariant.hovered)
            ? AppOpacity.light
            : AppOpacity.softTint;
        return AnimatedContainer(
          duration: AppMotionPolicy.duration(
            context,
            Motion.fast,
            role: AppMotionRole.decorative,
          ),
          curve: Motion.standardDecelerate,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              foreground.withValues(alpha: tint),
              colors.card,
            ),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: child,
        );
      },
      child: SizedBox(
        key: const ValueKey<String>('floating-nav.assistant'),
        height: height,
        width: width,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: foreground, size: AppIconSizes.md),
            if (label != null) ...[
              const SizedBox(width: AppSpacing.s6),
              Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypographyTokens.labelSmallMedium.copyWith(
                  color: foreground,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
