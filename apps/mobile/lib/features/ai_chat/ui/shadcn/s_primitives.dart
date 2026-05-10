import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 's_tokens.dart';

/// SCard — thin border + muted fill surface. Delegates colors to forui.
class SCard extends StatelessWidget {
  const SCard({
    super.key,
    required this.child,
    this.padding,
    this.background,
    this.borderColor,
    this.radius = SRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? background;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? colors.muted,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        border: Border.all(color: borderColor ?? colors.border, width: 1),
      ),
      child: child,
    );
  }
}

/// SBadge — small pill, forui-tinted.
class SBadge extends StatelessWidget {
  const SBadge({
    super.key,
    required this.label,
    this.background,
    this.foreground,
    this.icon,
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final fg = foreground ?? colors.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? colors.secondary,
        borderRadius: SRadius.brMd,
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
              height: 1.2,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// SAvatar — circular avatar w/ optional gradient bg + fallback glyph.
class SAvatar extends StatelessWidget {
  const SAvatar({
    super.key,
    this.size = 28,
    this.initial,
    this.icon,
    this.gradient,
    this.background,
    this.foreground,
  });

  final double size;
  final String? initial;
  final IconData? icon;
  final Gradient? gradient;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final fg = foreground ?? colors.foreground;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: gradient == null ? (background ?? colors.secondary) : null,
        gradient: gradient,
        border: Border.all(color: colors.border, width: 1),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: size * 0.55, color: fg)
          : Text(
              (initial ?? '·').toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.0,
              ),
            ),
    );
  }
}

/// SButton — compact button. Maps to FButton variants.
enum SButtonVariant { primary, outline, ghost, destructive }

class SButton extends StatelessWidget {
  const SButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.variant = SButtonVariant.outline,
    this.dense = false,
  });

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final SButtonVariant variant;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fVariant = switch (variant) {
      SButtonVariant.primary => FButtonVariant.primary,
      SButtonVariant.outline => FButtonVariant.outline,
      SButtonVariant.ghost => FButtonVariant.ghost,
      SButtonVariant.destructive => FButtonVariant.destructive,
    };
    return FButton(
      variant: fVariant,
      onPress: onPressed,
      prefix: icon != null ? Icon(icon, size: dense ? 12 : 14) : null,
      child: label != null
          ? Text(label!, style: TextStyle(fontSize: dense ? 12 : 13))
          : const SizedBox.shrink(),
    );
  }
}

/// SSeparator — thin hairline divider.
class SSeparator extends StatelessWidget {
  const SSeparator({super.key, this.thickness = 1, this.color});

  final double thickness;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: thickness,
      width: double.infinity,
      color: color ?? context.theme.colors.border,
    );
  }
}

/// SSkeleton — pulsing placeholder. Forui has no skeleton primitive.
class SSkeleton extends StatefulWidget {
  const SSkeleton({super.key, this.height = 14, this.width, this.radius = 4});

  final double height;
  final double? width;
  final double radius;

  @override
  State<SSkeleton> createState() => _SSkeletonState();
}

class _SSkeletonState extends State<SSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(colors.muted, colors.secondary, _ctrl.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// SCollapsible — single-section expand/collapse.
class SCollapsible extends StatefulWidget {
  const SCollapsible({
    super.key,
    required this.header,
    required this.child,
    this.initiallyExpanded = false,
  });

  final Widget header;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<SCollapsible> createState() => _SCollapsibleState();
}

class _SCollapsibleState extends State<SCollapsible>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: _expanded ? 1.0 : 0.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTappable(
          onPress: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SSpace.sm,
              vertical: SSpace.sm,
            ),
            child: Row(
              children: [
                Expanded(child: widget.header),
                RotationTransition(
                  turns: Tween(begin: 0.0, end: 0.25).animate(_ctrl),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: _ctrl,
              curve: Curves.easeOutCubic,
            ),
            axisAlignment: -1.0,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// SCodeBlock — monospace block w/ subtle muted fill. No forui equivalent.
class SCodeBlock extends StatelessWidget {
  const SCodeBlock({super.key, required this.text, this.maxLines});

  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SSpace.md),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: SRadius.brMd,
        border: Border.all(color: colors.border, width: 1),
      ),
      child: SelectableText(
        text,
        maxLines: maxLines,
        style: SType.code(context),
      ),
    );
  }
}
