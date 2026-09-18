import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Stateless conversation chrome shared with read-only Agent execution pages.
/// Does not create or observe a chat session.
class UserMessageSurface extends StatelessWidget {
  const UserMessageSurface({super.key, required this.text, this.onLongPress});
  final String text;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AdaptiveMaxWidth.narrow),
      child: Semantics(
        container: true,
        label: AppLocalizations.of(context).aiChatSemanticsUserMessage,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s14,
              vertical: AppSpacing.s10,
            ),
            decoration: BoxDecoration(
              color: context.theme.colors.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(AppRadius.lg),
                bottomRight: Radius.circular(AppRadius.sm),
              ),
            ),
            child: SelectableText(
              text,
              style: context.theme.typography.body.sm.copyWith(
                height: 1.5,
                color: context.theme.colors.primaryForeground,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
