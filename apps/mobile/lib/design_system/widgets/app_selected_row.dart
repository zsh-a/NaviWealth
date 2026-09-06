import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// Selection chrome without adding padding or another card surface.
class AppSelectedRow extends StatelessWidget {
  const AppSelectedRow({
    super.key,
    required this.selected,
    required this.child,
    this.color,
  });

  final bool selected;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.theme.colors.primary;
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(
              width: AppStroke.branch,
              color: selected
                  ? accent
                  : accent.withValues(alpha: AppOpacity.transparent),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
