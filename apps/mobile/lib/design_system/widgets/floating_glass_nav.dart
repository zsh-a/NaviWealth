import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'app_glass.dart';
import 'app_interaction.dart';

const double kFloatingGlassNavBarHeight = AppSpacing.s64;
const double _kDestinationHeight = 52;
const double _kIconSlotSize = 26;
const double _kAssistantLabelBreakpoint = 390;

/// A floating glass-morphism bottom navigation bar.
///
/// Renders as a compact, translucent dock that floats above the content. The
/// optional assistant action sits inside the same height as the tab
/// destinations so the dock does not cover page-level floating actions.
///
/// Tabs share the remaining width evenly. The optional assistant action is a
/// separate, low-emphasis affordance at the trailing edge so it never reads as
/// a selected navigation destination.
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

  @override
  Widget build(BuildContext context) {
    // One restrained frosted layer (shared glass tone — see appGlassDecoration
    // for the no-BackdropFilter rationale). Tonal contrast and a hairline
    // border do the hierarchy work; extra highlight gradients would make the
    // dock read glossier than the rest of the app.
    final glass = appGlassDecoration(
      context,
      borderRadius: BorderRadius.circular(AppRadius.full),
      boxShadow: AppShadow.nav,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactAssistant =
            constraints.maxWidth < _kAssistantLabelBreakpoint;
        return RepaintBoundary(
          child: Container(
            height: kFloatingGlassNavBarHeight,
            decoration: BoxDecoration(
              borderRadius: glass.borderRadius,
              border: glass.border,
              boxShadow: glass.boxShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: ColoredBox(
              color: glass.color!,
              child: Padding(
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
                          onTap: () => onIndexChanged(i),
                        ),
                      ),
                    if (onAssistantAction != null)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.s8),
                        child: _AssistantActionButton(
                          icon: assistantIcon,
                          label: compactAssistant ? null : assistantLabel,
                          semanticLabel: assistantSemanticLabel,
                          compact: compactAssistant,
                          onTap: onAssistantAction!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
  });

  final FloatingNavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final iconColor = selected ? colors.primary : colors.mutedForeground;
    final labelColor = selected ? colors.foreground : colors.mutedForeground;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: FTappable(
        onPress: () {
          if (!selected) {
            AppInteraction.signal(AppInteractionIntent.navigate);
          }
          onTap();
        },
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(
            context,
            Motion.fast,
            role: AppMotionRole.decorative,
          ),
          curve: Motion.standardDecelerate,
          height: _kDestinationHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s4,
          ),
          decoration: BoxDecoration(
            // Quiet selected state: whisper fill, not a loud brand pill.
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.faint)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: _kIconSlotSize,
                height: _kIconSlotSize,
                child: AnimatedSwitcher(
                  duration: AppMotionPolicy.duration(
                    context,
                    Motion.fast,
                    role: AppMotionRole.decorative,
                  ),
                  switchInCurve: Motion.standardDecelerate,
                  switchOutCurve: Motion.standardAccelerate,
                  child: Icon(
                    selected ? tab.selectedIcon : tab.icon,
                    key: ValueKey<bool>(selected),
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
                        .copyWith(color: labelColor, height: 1.15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String? label;
  final String? semanticLabel;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = colors.primary;

    return Semantics(
      button: true,
      label: semanticLabel ?? label ?? 'AI',
      child: FTappable(
        onPress: onTap,
        child: Container(
          key: const ValueKey<String>('floating-nav.assistant'),
          height: AppSpacing.s40,
          constraints: BoxConstraints(
            minWidth: compact ? AppSpacing.s40 : AppSpacing.s64,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.s8 : AppSpacing.s10,
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: AppIconSizes.h18),
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
      ),
    );
  }
}
