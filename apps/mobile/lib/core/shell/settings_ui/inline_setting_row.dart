import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';

/// Single-line setting row in iOS-style inset-grouped lists.
///
/// Layout: leading icon · label (Expanded) · trailing value chip · chevron.
/// Tap opens an anchored Forui [FPopover] right under the row with the
/// candidate values — proper dropdown affordance, not a bottom sheet
/// (which felt heavy for a 3-option theme switcher). The selection is
/// committed via [onChanged].
///
/// Use [InlineSwitchRow] when the trailing control is an on/off toggle —
/// same row chrome, no popup.
class InlineSettingRow<T> extends StatefulWidget {
  const InlineSettingRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.stackValue = false,
  });

  final IconData icon;
  final String label;
  final T value;
  final Map<String, T> options;
  final ValueChanged<T> onChanged;
  final String? subtitle;

  /// Places the selected value on its own line below [label].
  ///
  /// Use this for localized option labels that would otherwise compete with
  /// the setting label for one narrow mobile row. The whole surface remains a
  /// single anchored-popover target.
  final bool stackValue;

  @override
  State<InlineSettingRow<T>> createState() => _InlineSettingRowState<T>();
}

class _InlineSettingRowState<T> extends State<InlineSettingRow<T>>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _popover;

  @override
  void initState() {
    super.initState();
    _popover = FPopoverController(vsync: this);
  }

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final selectedLabel = widget.options.entries
        .firstWhere(
          (e) => e.value == widget.value,
          orElse: () => MapEntry(widget.value.toString(), widget.value),
        )
        .key;

    return FPopover(
      control: FPopoverControl.managed(controller: _popover),
      popoverAnchor: AlignmentDirectional.topEnd,
      childAnchor: AlignmentDirectional.bottomEnd,
      // Bound the portal so the popover always has a finite layout box.
      // Without explicit constraints, the inner Column.stretch + scroll
      // view chain leaves the portal child unsized and the first hit
      // test against it crashes.
      constraints: const FPortalConstraints(
        minWidth: 200,
        maxWidth: 320,
        maxHeight: 360,
      ),
      popoverBuilder: (popoverContext, _) => _PopoverContent<T>(
        options: widget.options,
        selected: widget.value,
        onPick: (picked) async {
          await _popover.hide();
          if (picked != widget.value) widget.onChanged(picked);
        },
      ),
      child: AppTappable(
        onPress: _popover.toggle,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: widget.subtitle == null ? AppSpacing.s10 : AppSpacing.s8,
          ),
          child: Row(
            crossAxisAlignment: widget.stackValue
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              _IconChip(icon: widget.icon, colors: colors),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: context.theme.typography.body.sm,
                      maxLines: widget.stackValue ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.s2),
                        child: Text(
                          widget.subtitle!,
                          style: context.captionStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (widget.stackValue) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedLabel,
                              style: context.bodyCaptionStyle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          Icon(
                            FLucideIcons.chevronDown,
                            size: AppIconSizes.xs,
                            color: colors.mutedForeground.withValues(
                              alpha: AppOpacity.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!widget.stackValue) ...[
                const SizedBox(width: AppSpacing.s10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 172),
                  child: Text(
                    selectedLabel,
                    style: context.bodyCaptionStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                Icon(
                  FLucideIcons.chevronDown,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground.withValues(
                    alpha: AppOpacity.muted,
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

/// Anchored option list rendered inside [FPopover]. Mirrors the visual
/// language of Forui's `FSelect` popover content (tight rows, check
/// icon on selected, hover tint), but built atop our own primitives so
/// the styling stays under our control.
class _PopoverContent<T> extends StatelessWidget {
  const _PopoverContent({
    required this.options,
    required this.selected,
    required this.onPick,
  });

  final Map<String, T> options;
  final T selected;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    // The outer FPortalConstraints already caps min/max width + height.
    // Here we just need a min-sized scroll view holding the rows; the
    // Column wraps naturally because the parent gives a bounded width.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in options.entries)
            _OptionRow<T>(
              label: entry.key,
              value: entry.value,
              isSelected: entry.value == selected,
              onTap: () => onPick(entry.value),
              accentColor: colors.primary,
            ),
        ],
      ),
    );
  }
}

/// One option inside the popover content. Stateless — the hover /
/// press feedback is delegated to [FTappable] which routes through
/// Forui's mouse-region handling. Doing the hover state ourselves with
/// a plain MouseRegion + setState raced against the mouse tracker
/// when the popover dismissed mid-frame.
class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onTap,
    required this.accentColor,
  });

  final String label;
  final T value;
  final bool isSelected;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AppTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            SizedBox(
              width: AppIconSizes.h18,
              child: isSelected
                  ? Icon(
                      FLucideIcons.check,
                      size: AppIconSizes.sm,
                      color: accentColor,
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                label,
                style: isSelected
                    ? context.labelStyle.copyWith(color: accentColor)
                    : context.theme.typography.body.sm.copyWith(
                        color: colors.foreground,
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single-line setting row with a trailing toggle. Same chrome as
/// [InlineSettingRow] so the surrounding section keeps a uniform
/// rhythm.
class InlineSwitchRow extends StatelessWidget {
  const InlineSwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s10,
      ),
      child: Row(
        children: [
          _IconChip(icon: icon, colors: colors),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: context.theme.typography.body.sm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s2),
                    child: Text(
                      subtitle!,
                      style: context.captionStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          FSwitch(
            value: value,
            enabled: enabled,
            onChange: (v) {
              AppInteraction.signal(AppInteractionIntent.select);
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

/// Single-line link row (no trailing value chip; just chevron). Same
/// chrome as [InlineSettingRow]. Use for navigation tiles inside an
/// inset-grouped section.
///
/// Three trailing-content modes — pick at most one:
///   * [trailingValue]  — muted gray text (e.g. "On", "CNY"). The
///                         classic chip slot.
///   * [trailingBadge]  — compact uppercase pill (e.g. "AUTO", "CUSTOM")
///                         in a soft tint. Replaces wordy subtitles that
///                         only convey state.
///   * [trailing]       — escape-hatch widget; use sparingly when
///                         neither of the above fits.
class InlineLinkRow extends StatelessWidget {
  const InlineLinkRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailingValue,
    this.trailingBadge,
    this.trailing,
    this.onTrailingTap,
  }) : assert(
         (trailingValue == null ? 0 : 1) +
                 (trailingBadge == null ? 0 : 1) +
                 (trailing == null ? 0 : 1) <=
             1,
         'InlineLinkRow accepts at most one of trailingValue / trailingBadge / trailing',
       );

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final String? trailingValue;
  final String? trailingBadge;
  final Widget? trailing;

  /// Called when [trailing] is tapped. Stops the tap from propagating
  /// to the row's [onTap]. Ignored when [trailing] is null.
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AppTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            _IconChip(icon: icon, colors: colors),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.theme.typography.body.sm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s2),
                      child: Text(
                        subtitle!,
                        style: context.captionStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (trailingValue != null) ...[
              const SizedBox(width: AppSpacing.s8),
              Flexible(
                child: Text(
                  trailingValue!,
                  style: context.bodyCaptionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ] else if (trailingBadge != null) ...[
              const SizedBox(width: AppSpacing.s8),
              AppBadge(
                label: trailingBadge!.toUpperCase(),
                size: AppBadgeSize.compact,
              ),
            ] else if (trailing != null) ...[
              const SizedBox(width: AppSpacing.s8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTrailingTap,
                child: trailing!,
              ),
            ],
            const SizedBox(width: AppSpacing.s4),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
              color: colors.mutedForeground.withValues(
                alpha: AppOpacity.prominent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tinted icon chip — gives settings row icons the same premium feel
/// as [AppActionSheetTile]. A 32x32 rounded container with a subtle
/// primary-tinted background makes each row feel more polished.
class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.colors});

  final IconData icon;
  final FColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.s32,
      height: AppSpacing.s32,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: AppIconSizes.sm, color: colors.primary),
    );
  }
}
