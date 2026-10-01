import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../application/knowledge_edit_service.dart';

String knowledgeEditFailureMessage(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  return switch (error) {
    KnowledgeEditFailure.changed => l10n.knowledgeEditChanged,
    KnowledgeEditFailure.missing => l10n.knowledgeObjectNotFound,
    _ => userSafeErrorMessage(
      context,
      error,
      operation: 'save knowledge entry',
    ),
  };
}

class KnowledgeEditNotice extends StatelessWidget {
  const KnowledgeEditNotice({
    super.key,
    required this.deleted,
    required this.onReload,
  });

  final bool deleted;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStatusBanner(
          key: const Key('knowledge-edit-change-notice'),
          message: deleted
              ? l10n.knowledgeEditDeletedDraft
              : l10n.knowledgeEditChanged,
          kind: AppStatusKind.warning,
        ),
        if (!deleted) ...[
          const SizedBox(height: AppSpacing.s8),
          FButton(
            key: const Key('knowledge-edit-reload'),
            variant: FButtonVariant.outline,
            onPress: onReload,
            child: Text(l10n.knowledgeEditReload),
          ),
        ],
        const SizedBox(height: AppSpacing.s12),
      ],
    );
  }
}
