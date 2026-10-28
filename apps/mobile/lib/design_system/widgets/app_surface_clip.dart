import 'package:flutter/widgets.dart';

/// Keeps form state when a live theme switches between clip families.
/// Each renderer retains its native rounded-rectangle/superellipse fast path.
class AppSurfaceClip extends StatefulWidget {
  const AppSurfaceClip({
    super.key,
    required this.continuous,
    required this.borderRadius,
    required this.child,
  });

  final bool continuous;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<AppSurfaceClip> createState() => _AppSurfaceClipState();
}

class _AppSurfaceClipState extends State<AppSurfaceClip> {
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    return widget.continuous
        ? ClipRSuperellipse(borderRadius: widget.borderRadius, child: content)
        : ClipRRect(borderRadius: widget.borderRadius, child: content);
  }
}
