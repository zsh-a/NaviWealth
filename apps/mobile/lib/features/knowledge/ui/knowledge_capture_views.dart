part of 'knowledge_capture_sheet.dart';

class _ComposeBody extends StatelessWidget {
  const _ComposeBody({
    required this.titleController,
    required this.bodyController,
    required this.bodyFocusNode,
    required this.aiAvailable,
    required this.onSaveOriginal,
  });
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final FocusNode bodyFocusNode;
  final bool aiAvailable;
  final VoidCallback? onSaveOriginal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeWriterSection(
      title: l10n.knowledgeCaptureTitle,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: titleController),
          label: Text(l10n.knowledgeCaptureTitleField),
          hint: l10n.knowledgeCaptureTitleHint,
        ),
        FTextField(
          control: FTextFieldControl.managed(controller: bodyController),
          focusNode: bodyFocusNode,
          label: Text(l10n.knowledgeCaptureBodyField),
          hint: l10n.knowledgeCaptureBodyHint,
          minLines: 4,
          maxLines: 8,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KnowledgeImageInsertButton(controller: bodyController),
              SpeechInputButton(controller: bodyController),
            ],
          ),
        ),
        if (aiAvailable)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                FLucideIcons.fileText,
                size: AppIconSizes.sm,
                color: context.theme.colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  l10n.knowledgeCaptureAiOrganizationHint,
                  style: context.bodyCaptionStyle,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppQuietButton(
                label: l10n.knowledgeCaptureSaveWithoutAi,
                onPress: onSaveOriginal,
              ),
            ],
          ),
      ],
    );
  }
}

class _CaptureProgressBody extends StatelessWidget {
  const _CaptureProgressBody({this.saving = false});

  final bool saving;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FCircularProgress(),
          const SizedBox(height: AppSpacing.s16),
          Text(
            saving ? l10n.commonSaving : l10n.knowledgeCaptureOrganizingBody,
            style: context.bodyCaptionStyle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OrganizedReviewBody extends StatelessWidget {
  const _OrganizedReviewBody({
    required this.titleController,
    required this.bodyController,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeWriterSection(
      title: l10n.knowledgeCaptureReviewDraftTitle,
      subtitle: l10n.knowledgeCaptureReviewDraftSubtitle,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: titleController),
          label: Text(l10n.knowledgeCaptureTitleDiffLabel),
        ),
        MarkdownEditorWithPreview(
          controller: bodyController,
          label: l10n.knowledgeCaptureBodyDiffLabel,
          minLines: 6,
          maxLines: 12,
          initialPreview: true,
        ),
      ],
    );
  }
}
