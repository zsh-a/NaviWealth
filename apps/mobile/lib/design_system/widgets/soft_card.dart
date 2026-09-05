import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_data.dart';
import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'app_interaction.dart';
import 'spring_press_scale.dart';

enum SoftCardLevel { flat, raised, hero }

/// Calm surface container for dense financial UIs.
///
/// Levels form a deliberate elevation ladder:
/// - [SoftCardLevel.flat] — quiet list rows, dissolves into the page
/// - [SoftCardLevel.raised] — primary dashboard modules
/// - [SoftCardLevel.hero] — the single visual anchor on a surface
///
/// Interactive cards get a soft press scale + tonal shift (no Material ripple).
class SoftCard extends StatefulWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onPress,
    this.borderRadius,
    this.tinted = true,
    this.level = SoftCardLevel.flat,
  });

  /// Dense list row / nested surface — no elevation.
  const SoftCard.flat({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    VoidCallback? onPress,
    double? borderRadius,
    bool tinted = true,
  }) : this(
         key: key,
         child: child,
         padding: padding,
         onPress: onPress,
         borderRadius: borderRadius,
         tinted: tinted,
         level: SoftCardLevel.flat,
       );

  /// Primary dashboard module.
  ///
  /// Padding defaults to zero so existing call sites that nest their own
  /// [Padding] do not double-inset. Prefer [AppPageRhythm.cardPadding] at
  /// call sites for new modules.
  const SoftCard.raised({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    VoidCallback? onPress,
    double? borderRadius,
    bool tinted = true,
  }) : this(
         key: key,
         child: child,
         padding: padding,
         onPress: onPress,
         borderRadius: borderRadius,
         tinted: tinted,
         level: SoftCardLevel.raised,
       );

  /// Single page-level visual anchor.
  ///
  /// Prefer [AppPageRhythm.heroPadding] when the card owns its content inset.
  const SoftCard.hero({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    VoidCallback? onPress,
    double? borderRadius,
    bool tinted = true,
  }) : this(
         key: key,
         child: child,
         padding: padding,
         onPress: onPress,
         borderRadius: borderRadius,
         tinted: tinted,
         level: SoftCardLevel.hero,
       );

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onPress;

  /// Override corner radius. When null, resolves from [level] via
  /// `theme.card`: flat/raised → [AppRadius.md], hero → [AppRadius.lg].
  final double? borderRadius;

  /// Apply the level's surface fill. Disable for nested rows that sit
  /// inside an already-tinted parent.
  final bool tinted;

  /// Visual depth. Prefer one [SoftCardLevel.hero] per screen.
  final SoftCardLevel level;

  @override
  State<SoftCard> createState() => _SoftCardState();
}

class _SoftCardState extends State<SoftCard> {
  final ValueNotifier<bool> _hovered = ValueNotifier(false);
  final ValueNotifier<bool> _pressed = ValueNotifier(false);
  final ValueNotifier<bool> _focused = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    _pressed.dispose();
    _focused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onPress == null) {
      return _buildStaticCard(context);
    }

    // Keyboard parity (doc 11 §9): interactive cards are focusable, show a
    // focus ring, and activate on Enter/Space with the same haptic grammar
    // as a tap.
    return Semantics(
      button: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => _hovered.value = value,
        onShowFocusHighlight: (value) => _focused.value = value,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              AppInteraction.wrap(
                widget.onPress,
                intent: AppInteractionIntent.select,
              )?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _pressed.value = true,
          onTapUp: (_) => _pressed.value = false,
          onTapCancel: () => _pressed.value = false,
          onTap: AppInteraction.wrap(
            widget.onPress,
            intent: AppInteractionIntent.select,
          ),
          child: ListenableBuilder(
            listenable: Listenable.merge([_hovered, _pressed, _focused]),
            builder: (context, _) => _buildCard(
              context,
              hovered: _hovered.value,
              pressed: _pressed.value,
              focused: _focused.value,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaticCard(BuildContext context) {
    return DecoratedBox(
      decoration: _decoration(
        context,
        hovered: false,
        pressed: false,
        focused: false,
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool hovered,
    required bool pressed,
    required bool focused,
  }) {
    final duration = AppMotionPolicy.duration(
      context,
      Motion.fast,
      role: AppMotionRole.decorative,
    );
    return SpringPressScale(
      pressed: pressed,
      child: AnimatedContainer(
        duration: duration,
        curve: Motion.standardDecelerate,
        decoration: _decoration(
          context,
          hovered: hovered,
          pressed: pressed,
          focused: focused,
        ),
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }

  BoxDecoration _decoration(
    BuildContext context, {
    required bool hovered,
    required bool pressed,
    required bool focused,
  }) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final card = context.appTheme.card;
    final radius = BorderRadius.circular(
      widget.borderRadius ??
          (widget.level == SoftCardLevel.hero ? card.heroRadius : card.radius),
    );

    final baseFill = widget.tinted
        ? _surfaceFill(context.appTheme.surfaces)
        : Colors.transparent;

    final hoverBoost = isDark ? AppOpacity.hoverTintDark : AppOpacity.hoverTint;
    final interactive = widget.onPress != null && (hovered || pressed);
    final fill = interactive && widget.tinted
        ? Color.alphaBlend(
            colors.foreground.withValues(
              alpha: pressed ? AppOpacity.faint : hoverBoost,
            ),
            baseFill,
          )
        : interactive && !widget.tinted
        ? colors.foreground.withValues(alpha: hoverBoost)
        : baseFill;

    // One border strategy for the whole app (blueprint §8.3):
    // raised = borderless + shadow (fill difference carries dark mode),
    // flat = whisper edge in dark only, hero = a quiet edge with depth carried by the surface.
    final borderAlpha = switch (widget.level) {
      SoftCardLevel.flat =>
        isDark ? AppOpacity.whisper : AppOpacity.transparent,
      SoftCardLevel.raised => AppOpacity.transparent,
      SoftCardLevel.hero => isDark ? AppOpacity.subtle : AppOpacity.light,
    };

    final borderColor = borderAlpha == AppOpacity.transparent
        ? Colors.transparent
        : (isDark
              // Resolve dark borders from the foreground. Applying opacity to
              // the already-dark border token made raised and hero cards
              // visually indistinguishable from the canvas.
              ? colors.foreground.withValues(alpha: borderAlpha)
              : ColorPalette.surfaceHairline.withValues(alpha: borderAlpha));

    final gradient = widget.level == SoftCardLevel.hero && widget.tinted
        ? _heroGradient(primary: colors.primary, base: fill)
        : null;

    // Keyboard focus ring wins over the level border (doc 11 §9).
    final border = focused
        ? Border.all(color: colors.primary, width: AppStroke.branch)
        : borderAlpha == AppOpacity.transparent
        ? null
        : Border.all(color: borderColor, width: AppStroke.hairline);

    return BoxDecoration(
      color: gradient == null ? fill : null,
      gradient: gradient,
      borderRadius: radius,
      border: border,
      boxShadow: _shadows(isDark: isDark, hovered: hovered, pressed: pressed),
    );
  }

  Color _surfaceFill(AppSurfaces surfaces) => switch (widget.level) {
    SoftCardLevel.flat => surfaces.card,
    SoftCardLevel.raised => surfaces.raised,
    SoftCardLevel.hero => surfaces.hero,
  };

  LinearGradient _heroGradient({required Color primary, required Color base}) {
    // A small directional wash preserves the page anchor without tinting
    // the whole card or competing with its data.
    final wash = primary.withValues(alpha: AppOpacity.faint);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.alphaBlend(wash, base), base],
      stops: const [0, 0.62],
    );
  }

  List<BoxShadow>? _shadows({
    required bool isDark,
    required bool hovered,
    required bool pressed,
  }) {
    final level = pressed && widget.onPress != null
        ? SoftCardLevel.flat
        : widget.level;
    return switch (level) {
      SoftCardLevel.flat => null,
      SoftCardLevel.raised =>
        isDark
            ? AppShadow.cardDark
            : hovered && widget.onPress != null
            ? AppShadow.cardHover
            : AppShadow.card,
      SoftCardLevel.hero => isDark ? AppShadow.heroDark : AppShadow.hero,
    };
  }
}
