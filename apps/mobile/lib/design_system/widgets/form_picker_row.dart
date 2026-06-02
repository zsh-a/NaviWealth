import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Form row for values chosen from a picker instead of typed directly.
///
/// Keeps date/account/category-style fields visually aligned with text fields:
/// label above, current value below, and a trailing affordance.
class FormPickerRow extends StatefulWidget {
  const FormPickerRow({
    super.key,
    required this.label,
    required this.value,
    this.onPress,
    this.leading,
    this.trailing,
    this.enabled = true,
  });

  final String label;
  final String value;
  final VoidCallback? onPress;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;

  @override
  State<FormPickerRow> createState() => _FormPickerRowState();
}

class _FormPickerRowState extends State<FormPickerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final enabled = widget.enabled && widget.onPress != null;
    final active = enabled && _hovered;
    final tint = active
        ? colors.primary.withValues(alpha: AppOpacity.faint)
        : colors.foreground.withValues(alpha: AppOpacity.whisper);
    final border = active
        ? colors.primary.withValues(alpha: AppOpacity.muted)
        : colors.border;

    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: FTappable(
        onPress: enabled ? widget.onPress : null,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standardDecelerate,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s10,
          ),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: AppSpacing.s10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: context.theme.typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      widget.value,
                      style: context.theme.typography.sm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              widget.trailing ??
                  Icon(
                    FLucideIcons.chevronDown,
                    size: AppIconSizes.sm,
                    color: colors.mutedForeground,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
