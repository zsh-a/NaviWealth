import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../../core/haptics/haptics.dart';
import '../tokens/color_palette.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/spacing_tokens.dart';
import 'floating_pill_navigation_bar.dart';

/// A single action item displayed in the [SuperFab] speed-dial popup.
class SuperFabAction {
  const SuperFabAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Central floating action button with a vertical speed-dial popup that
/// expands action items above the FAB.
///
/// Resting state: 56dp circle with a subtle pulse animation.
/// Expanded state: staggered vertical list with frosted scrim backdrop.
class SuperFab extends StatefulWidget {
  const SuperFab({super.key, required this.actions, this.enablePulse = true});

  final List<SuperFabAction> actions;

  /// Whether the resting-state pulse animation plays. Disable in tests to
  /// avoid pending timers from the looping animation controller.
  final bool enablePulse;

  /// Global override to disable pulse animation across all instances.
  /// Useful in tests to avoid pending timer assertions.
  static bool disablePulseGlobally = false;

  /// The diameter of the FAB button, exposed for layout calculations.
  static const double fabSize = 56;

  @override
  State<SuperFab> createState() => _SuperFabState();
}

const double _actionHeight = 52.0;
const double _actionGap = 10.0;
const double _actionHorizontalPadding = 16.0;

class _SuperFabState extends State<SuperFab> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _popupController;
  bool _isOpen = false;
  OverlayEntry? _overlayEntry;

  static const double _fabSize = SuperFab.fabSize;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Motion.ticker,
      vsync: this,
    );
    _popupController = AnimationController(
      duration: Motion.medium,
      vsync: this,
    );
    if (widget.enablePulse && !SuperFab.disablePulseGlobally) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _pulseController.dispose();
    _popupController.dispose();
    super.dispose();
  }

  void _insertOverlay() {
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (_) => _SpeedDialOverlay(
        animation: _popupController,
        actions: widget.actions,
        actionHeight: _actionHeight,
        actionGap: _actionGap,
        onDismiss: _dismiss,
        onActionTap: (action) {
          _dismiss();
          action.onTap();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _toggle() {
    Haptics.primaryPress();
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _pulseController.stop();
      _insertOverlay();
      _popupController.forward();
    } else {
      _popupController.reverse().then((_) {
        _removeOverlay();
        if (mounted && widget.enablePulse && !SuperFab.disablePulseGlobally) {
          _pulseController.repeat(reverse: true);
        }
      });
    }
  }

  void _dismiss() {
    if (_isOpen) _toggle();
  }

  @override
  Widget build(BuildContext context) {
    return _buildFabButton();
  }

  Widget _buildFabButton() {
    return RepaintBoundary(
      child: AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _isOpen ? 1.0 : 1.0 + 0.04 * _pulseController.value;
        return Transform.scale(scale: pulse, child: child);
      },
      child: GestureDetector(
        onTap: _toggle,
        child: AnimatedContainer(
          duration: Motion.slow,
          curve: Motion.liquidPress,
          width: _fabSize,
          height: _fabSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isOpen ? ColorPalette.brand600 : ColorPalette.brand500,
            boxShadow: [
              BoxShadow(
                color: ColorPalette.brand500.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0, // 45° rotation for "+" → "×"
            duration: Motion.medium,
            curve: Motion.emphasizedDecelerate,
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
        ),
      ),
    ),
    );
  }
}

/// Overlay widget that renders the speed-dial menu and scrim.
class _SpeedDialOverlay extends StatelessWidget {
  const _SpeedDialOverlay({
    required this.animation,
    required this.actions,
    required this.actionHeight,
    required this.actionGap,
    required this.onDismiss,
    required this.onActionTap,
  });

  final Animation<double> animation;
  final List<SuperFabAction> actions;
  final double actionHeight;
  final double actionGap;
  final VoidCallback onDismiss;
  final ValueChanged<SuperFabAction> onActionTap;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    // Position above the floating nav bar's top edge.
    const barInset = FloatingPillNavigationBar.overlayBottomInset;
    const floatGap = 20.0;
    const gap = 4.0;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOut.transform(animation.value);
        return Stack(
          children: [
            // Scrim — soft dim + blur, tap to dismiss.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16 * t, sigmaY: 16 * t),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.25 * t),
                  ),
                ),
              ),
            ),
            // Action items — positioned above the nav bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: barInset + floatGap + bottomSafe + gap,
              child: _buildActionList(context, t),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionList(BuildContext context, double globalT) {
    final total = actions.length;
    const staggerStep = 0.08;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < total; i++)
          _buildActionItem(context, actions[i], i, total, staggerStep),
      ],
    );
  }

  Widget _buildActionItem(
    BuildContext context,
    SuperFabAction action,
    int index,
    int total,
    double staggerStep,
  ) {
    final reversedIndex = total - 1 - index;
    final stagger = reversedIndex * staggerStep;
    final itemT = (animation.value - stagger).clamp(0.0, 1.0);
    final curved = Curves.easeOutCubic.transform(itemT);

    final slideOffset = (1 - curved) * 24.0;
    final opacity = itemT.clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, slideOffset),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: _actionGap),
        child: _GlassActionChip(
          action: action,
          height: actionHeight,
          onTap: () => onActionTap(action),
        ),
      ),
    );
  }
}

/// Apple-glass style action chip: frosted background, soft glow, refined icon.
class _GlassActionChip extends StatelessWidget {
  const _GlassActionChip({
    required this.action,
    required this.height,
    required this.onTap,
  });

  final SuperFabAction action;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: lgw.GlassContainer(
        useOwnLayer: true,
        quality: lgw.GlassQuality.minimal,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: Spacing.s24),
        padding: const EdgeInsets.symmetric(horizontal: _actionHorizontalPadding),
        shape: const lgw.LiquidRoundedSuperellipse(borderRadius: Radii.full),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ColorPalette.brand500.withValues(alpha: 0.15),
              ),
              alignment: Alignment.center,
              child: Icon(action.icon, size: 18, color: ColorPalette.brand500),
            ),
            const SizedBox(width: Spacing.s12),
            Flexible(
              child: Text(
                action.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : theme.colorScheme.onSurface,
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
