import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/haptics/haptics.dart';
import '../tokens/color_palette.dart';
import '../tokens/glass_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'glass_surface.dart';

/// A single action item displayed in the [SuperFab] radial popup.
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

/// Central floating action button with a radial popup that fans out
/// action items in a semicircle above the FAB.
///
/// Resting state: 56dp circle with a subtle pulse animation.
/// Expanded state: staggered scale+fade per action item with scrim backdrop.
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

class _SuperFabState extends State<SuperFab> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _popupController;
  bool _isOpen = false;
  OverlayEntry? _scrimEntry;

  static const double _fabSize = SuperFab.fabSize;
  static const double _actionSize = 48;
  static const double _radius = 96;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Motion.ticker,
      vsync: this,
    );
    _popupController = AnimationController(
      duration: Motion.slow,
      vsync: this,
    );
    if (widget.enablePulse && !SuperFab.disablePulseGlobally) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _removeScrim();
    _pulseController.dispose();
    _popupController.dispose();
    super.dispose();
  }

  void _insertScrim() {
    _scrimEntry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: _popupController,
        builder: (context, _) => GestureDetector(
          onTap: _dismiss,
          behavior: HitTestBehavior.translucent,
          child: Container(
            color: Colors.black.withValues(
              alpha: 0.25 * _popupController.value,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_scrimEntry!);
  }

  void _removeScrim() {
    _scrimEntry?.remove();
    _scrimEntry = null;
  }

  void _toggle() {
    Haptics.primaryPress();
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _pulseController.stop();
      _insertScrim();
      _popupController.forward();
    } else {
      _popupController.reverse().then((_) {
        _removeScrim();
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
    final actions = widget.actions;
    final total = actions.length;

    // Layout: FAB at bottom-center, actions fan out in a semicircle above.
    // Coordinate origin = FAB center.
    // Stack size: width spans the full diameter + action overflow,
    // height spans FAB + radius upward + action overflow.
    const stackW = _radius * 2 + _actionSize + _fabSize;
    const stackH = _radius + _actionSize + _fabSize;
    const fabCenterX = stackW / 2;
    const fabCenterY = stackH - _fabSize / 2;

    // Semicircle from left to right, above the FAB.
    const startAngle = math.pi; // left (180°)
    const endAngle = 0.0; // right (0°)

    return SizedBox(
      width: stackW,
      height: stackH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Radial action items.
          for (int i = 0; i < total; i++)
            _buildActionItem(
              actions[i],
              i,
              total,
              startAngle,
              endAngle,
              fabCenterX,
              fabCenterY,
            ),
          // Central FAB.
          Positioned(
            left: fabCenterX - _fabSize / 2,
            top: fabCenterY - _fabSize / 2,
            child: _buildFabButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(
    SuperFabAction action,
    int index,
    int total,
    double startAngle,
    double endAngle,
    double fabCX,
    double fabCY,
  ) {
    // Distribute evenly across the semicircle.
    final t = total > 1 ? index / (total - 1) : 0.5;
    final angle = startAngle + (endAngle - startAngle) * t;
    final targetX = _radius * math.cos(angle);
    final targetY = -_radius * math.sin(angle); // screen Y is inverted

    // Stagger: each item appears 12% after the previous.
    final stagger = index * 0.12;

    return AnimatedBuilder(
      animation: _popupController,
      builder: (context, _) {
        final raw = _popupController.value;
        final itemT = (raw - stagger).clamp(0.0, 1.0);
        final curved = Curves.easeOutBack.transform(itemT);

        final dx = targetX * curved;
        final dy = targetY * curved;
        final scale = itemT < 0.01 ? 0.0 : curved.clamp(0.0, 1.2);
        final opacity = itemT.clamp(0.0, 1.0);

        // Position: action center = FAB center + offset.
        final cx = fabCX + dx;
        final cy = fabCY + dy;

        return Positioned(
          left: cx - _actionSize / 2,
          top: cy - _actionSize / 2 - 12, // 12px label space below
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: _ActionBubble(
                action: action,
                size: _actionSize,
                onTap: () {
                  _dismiss();
                  action.onTap();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFabButton() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _isOpen ? 1.0 : 1.0 + 0.04 * _pulseController.value;
        return Transform.scale(scale: pulse, child: child);
      },
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          width: _fabSize,
          height: _fabSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [ColorPalette.brand400, ColorPalette.brand600],
            ),
            boxShadow: [
              BoxShadow(
                color: ColorPalette.brand500.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0,
            duration: Motion.medium,
            curve: Motion.emphasizedDecelerate,
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

class _ActionBubble extends StatelessWidget {
  const _ActionBubble({
    required this.action,
    required this.size,
    required this.onTap,
  });

  final SuperFabAction action;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<GlassTokens>() ?? GlassTokens.light();
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassSurface(
            sigma: 16,
            borderRadius: BorderRadius.circular(size / 2),
            border: Border.all(color: tokens.hairlineColor, width: 1),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              child: Icon(action.icon, size: 22, color: colorScheme.onSurface),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            action.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
