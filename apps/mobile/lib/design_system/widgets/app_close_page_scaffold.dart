import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// Fullscreen page shell with a close action instead of back navigation.
class AppClosePageScaffold extends StatelessWidget {
  const AppClosePageScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.childPad = false,
  });

  final String title;
  final Widget child;
  final VoidCallback onClose;
  final bool childPad;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader.nested(
        title: Text(title),
        prefixes: [
          FHeaderAction(icon: const Icon(FLucideIcons.x), onPress: onClose),
        ],
      ),
      childPad: childPad,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: child,
        ),
      ),
    );
  }
}
