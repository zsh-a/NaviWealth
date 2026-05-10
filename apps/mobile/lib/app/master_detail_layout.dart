import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../design_system/design_system.dart';
import 'shell_preferences.dart';

/// Two-pane master-detail surface used by the desktop shell at ≥ 1240dp.
/// The list pane lives on the left at the user's preferred width
/// (clamped 320–520) and the detail pane fills the remainder. A draggable
/// hairline between the two acts as the splitter.
///
/// At narrower widths each consumer falls back to its single-column
/// rendering — this widget is only mounted when [shouldUseMasterDetail]
/// returns true.
class MasterDetailLayout extends ConsumerWidget {
  const MasterDetailLayout({
    super.key,
    required this.master,
    required this.detail,
  });

  final Widget master;
  final Widget detail;

  static bool shouldUseMasterDetail(double width) =>
      width >= Breakpoints.desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masterWidth = ref.watch(masterPaneWidthProvider);
    final colors = context.theme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: masterWidth, child: master),
        _Splitter(
          color: colors.border,
          width: masterWidth,
          onChanged: (delta) {
            ref.read(masterPaneWidthProvider.notifier).set(masterWidth + delta);
          },
        ),
        Expanded(child: detail),
      ],
    );
  }
}

class _Splitter extends StatefulWidget {
  const _Splitter({
    required this.color,
    required this.width,
    required this.onChanged,
  });

  final Color color;
  final double width;
  final ValueChanged<double> onChanged;

  @override
  State<_Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<_Splitter> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final highlight = _hovering || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (d) => widget.onChanged(d.delta.dx),
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: highlight ? 2 : 1,
              color: highlight ? context.theme.colors.primary : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state shown in the detail pane when nothing is selected.
class MasterDetailEmpty extends StatelessWidget {
  const MasterDetailEmpty({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.touch_app_outlined,
              size: 36,
              color: colors.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: typography.sm.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
