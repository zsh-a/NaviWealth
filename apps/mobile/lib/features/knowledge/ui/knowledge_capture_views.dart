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

class _OrganizedReviewBody extends StatefulWidget {
  const _OrganizedReviewBody({
    required this.titleController,
    required this.bodyController,
    required this.originalTitle,
    required this.originalBody,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;
  final String originalTitle;
  final String originalBody;

  @override
  State<_OrganizedReviewBody> createState() => _OrganizedReviewBodyState();
}

class _OrganizedReviewBodyState extends State<_OrganizedReviewBody> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeWriterSection(
      title: l10n.knowledgeCaptureReviewDraftTitle,
      subtitle: l10n.knowledgeCaptureReviewDraftSubtitle,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _showOriginal
                    ? l10n.knowledgeCaptureOriginalVersion
                    : l10n.knowledgeCaptureOrganizedVersion,
                style: context.labelStyle,
              ),
            ),
            AppQuietButton(
              label: _showOriginal
                  ? l10n.knowledgeCaptureShowOrganized
                  : l10n.knowledgeCaptureShowOriginal,
              onPress: () => setState(() => _showOriginal = !_showOriginal),
            ),
          ],
        ),
        if (_showOriginal)
          Container(
            padding: AppPageRhythm.densePadding,
            decoration: BoxDecoration(
              color: context.theme.colors.muted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.theme.colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.originalTitle.isEmpty
                      ? l10n.knowledgeCaptureUntitledOriginal
                      : widget.originalTitle,
                  style: TypographyTokens.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.s12),
                KnowledgeMarkdown(text: widget.originalBody),
              ],
            ),
          )
        else ...[
          FTextField(
            control: FTextFieldControl.managed(
              controller: widget.titleController,
            ),
            label: Text(l10n.knowledgeCaptureTitleDiffLabel),
          ),
          MarkdownEditorWithPreview(
            controller: widget.bodyController,
            label: l10n.knowledgeCaptureBodyDiffLabel,
            minLines: 6,
            maxLines: 12,
            initialPreview: true,
          ),
        ],
      ],
    );
  }
}
