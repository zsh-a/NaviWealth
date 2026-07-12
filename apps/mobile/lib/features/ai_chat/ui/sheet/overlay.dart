part of 'ai_sheet.dart';

/// Bottom-sheet frame that stays usable while the soft keyboard is up.
///
/// `showFSheet` slides a fixed-height box up from the bottom. This
/// route opts out of forui's automatic inset shifting so keyboard
/// avoidance has a single owner here: without compensation the composer
/// / footer buttons sit behind the keyboard and can't be tapped. This frame:
///
///  - reads `viewInsets` *inside* the subtree so it rebuilds when the
///    keyboard toggles,
///  - grows the sheet toward full height while the keyboard is open so
///    the conversation keeps usable room, and
///  - pads the body up by the keyboard height so the composer/footer
///    rest just above it.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final screenH = mq.size.height;
    // Short viewports open full-height (matches the old invocation
    // rule); otherwise 70 vh, expanding by the keyboard height (capped
    // near full screen) so the visible area doesn't collapse.
    final base = screenH < 500 ? screenH : screenH * 0.7;
    final height = keyboard > 0
        ? math.min(screenH * 0.95, base + keyboard)
        : base;
    return SizedBox(
      height: height,
      child: AnimatedPadding(
        duration: AppMotionPolicy.duration(context, Motion.fast),
        curve: AiMotion.standard,
        padding: EdgeInsets.only(bottom: keyboard),
        child: child,
      ),
    );
  }
}

/// Desktop conversation overlay: a 480 x 600 draggable floating card.
/// Position defaults to bottom-right and persists to SharedPreferences.
class _DesktopSheetOverlay extends ConsumerStatefulWidget {
  const _DesktopSheetOverlay({this.prefill});

  final String? prefill;

  @override
  ConsumerState<_DesktopSheetOverlay> createState() =>
      _DesktopSheetOverlayState();
}

class _DesktopSheetOverlayState extends ConsumerState<_DesktopSheetOverlay> {
  static const _prefKey = 'naviwealth.ai_chat.sheet_offset';

  // Default + bounds for the resizable sheet. The min keeps the
  // composer + at least one bubble visible; the max stops the user
  // from dragging it beyond a usable second-window size.
  static const Size _defaultSize = Size(480, 600);
  static const Size _minSize = Size(360, 420);
  static const Size _maxSize = Size(880, 960);

  Offset? _offset;
  Size? _size;

  @override
  void initState() {
    super.initState();
    _loadPersisted();
  }

  Future<void> _loadPersisted() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final dx = prefs.getDouble('$_prefKey.dx');
    final dy = prefs.getDouble('$_prefKey.dy');
    final w = prefs.getDouble('$_prefKey.w');
    final h = prefs.getDouble('$_prefKey.h');
    if (!mounted) return;
    setState(() {
      if (dx != null && dy != null) _offset = Offset(dx, dy);
      if (w != null && h != null) _size = Size(w, h);
    });
  }

  Future<void> _persistPosition(Offset o) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setDouble('$_prefKey.dx', o.dx),
      prefs.setDouble('$_prefKey.dy', o.dy),
    ]);
  }

  Future<void> _persistSize(Size s) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setDouble('$_prefKey.w', s.width),
      prefs.setDouble('$_prefKey.h', s.height),
    ]);
  }

  Size _effectiveSize() {
    final s = _size ?? _defaultSize;
    return Size(
      s.width.clamp(_minSize.width, _maxSize.width),
      s.height.clamp(_minSize.height, _maxSize.height),
    );
  }

  Offset _defaultPosition(Size screenSize, Size sheetSize) {
    return Offset(
      screenSize.width - sheetSize.width - 24,
      screenSize.height - sheetSize.height - 24,
    );
  }

  Offset _clampToScreen(Offset o, Size screenSize, Size sheetSize) {
    final maxDx = (screenSize.width - sheetSize.width).clamp(
      0.0,
      double.infinity,
    );
    final maxDy = (screenSize.height - sheetSize.height).clamp(
      0.0,
      double.infinity,
    );
    return Offset(o.dx.clamp(0.0, maxDx), o.dy.clamp(0.0, maxDy));
  }

  void _onHeaderDrag(DragUpdateDetails details, Size screenSize) {
    final sheetSize = _effectiveSize();
    final base = _offset ?? _defaultPosition(screenSize, sheetSize);
    setState(() {
      _offset = _clampToScreen(
        Offset(base.dx + details.delta.dx, base.dy + details.delta.dy),
        screenSize,
        sheetSize,
      );
    });
  }

  void _onHeaderDragEnd() {
    final o = _offset;
    if (o != null) _persistPosition(o);
  }

  void _onResize(DragUpdateDetails details) {
    final cur = _effectiveSize();
    setState(() {
      _size = Size(
        (cur.width + details.delta.dx).clamp(_minSize.width, _maxSize.width),
        (cur.height + details.delta.dy).clamp(_minSize.height, _maxSize.height),
      );
    });
  }

  void _onResizeEnd(Size screenSize) {
    final s = _effectiveSize();
    _persistSize(s);
    // Resize-bigger may push the existing top-left position past the
    // screen edge, so re-clamp + persist for the next open.
    final o = _offset;
    if (o != null) {
      final clamped = _clampToScreen(o, screenSize, s);
      if (clamped != o) {
        setState(() => _offset = clamped);
        _persistPosition(clamped);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final sheetSize = _effectiveSize();
    final basePos = _offset ?? _defaultPosition(screenSize, sheetSize);
    final pos = _clampToScreen(basePos, screenSize, sheetSize);
    // If the window shrank since last session and the persisted offset
    // now sits offscreen, write back the clamped offset so we don't
    // re-clamp on every build.
    if (_offset != null && pos != _offset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _offset = pos);
        _persistPosition(pos);
      });
    }

    final colors = context.theme.colors;
    return Stack(
      children: [
        Positioned(
          left: pos.dx,
          top: pos.dy,
          width: sheetSize.width,
          height: sheetSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: colors.border,
                  width: AppStroke.hairline,
                ),
                boxShadow: AppShadow.desktopSheet,
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Full-width draggable header strip. Anywhere on
                      // the top hit area counts as a drag handle.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (d) => _onHeaderDrag(d, screenSize),
                        onPanEnd: (_) => _onHeaderDragEnd(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: SizedBox(
                            height: AppControlHeights.sheetDragHandleHitArea,
                            child: AppSheetDragHandle(colors: colors),
                          ),
                        ),
                      ),
                      Expanded(
                        child: AiSheetShell.conversation(
                          prefill: widget.prefill,
                        ),
                      ),
                    ],
                  ),
                  // SE-corner resize affordance: three short diagonal
                  // strokes, with a hit area extending past the visual.
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: _onResize,
                      onPanEnd: (_) => _onResizeEnd(screenSize),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: SizedBox(
                          width: AppIconSizes.mlg,
                          height: AppIconSizes.mlg,
                          child: CustomPaint(
                            painter: _ResizeGripPainter(
                              color: colors.mutedForeground.withValues(
                                alpha: AppOpacity.scrim,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints three short diagonal strokes in the bottom-right corner so
/// the user can see where to grab to resize.
class _ResizeGripPainter extends CustomPainter {
  _ResizeGripPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = AppStroke.medium
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w - 14, h - 4), Offset(w - 4, h - 14), paint);
    canvas.drawLine(Offset(w - 10, h - 4), Offset(w - 4, h - 10), paint);
    canvas.drawLine(Offset(w - 6, h - 4), Offset(w - 4, h - 6), paint);
  }

  @override
  bool shouldRepaint(_ResizeGripPainter old) => old.color != color;
}
