part of 'knowledge_capture_sheet.dart';

class _ComposeBody extends StatelessWidget {
  const _ComposeBody({
    required this.titleController,
    required this.bodyController,
    required this.bodyFocusNode,
    required this.aiAvailable,
    required this.onSaveOriginal,
    required this.restoredDraft,
    required this.draftDiscarded,
    required this.onDiscardDraft,
  });
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final FocusNode bodyFocusNode;
  final bool aiAvailable;
  final VoidCallback? onSaveOriginal;
  final bool restoredDraft;
  final bool draftDiscarded;
  final VoidCallback onDiscardDraft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeWriterSection(
      title: l10n.knowledgeCaptureTitle,
      children: [
        if (restoredDraft)
          Row(
            children: [
              Icon(
                FLucideIcons.history,
                size: AppIconSizes.xs,
                color: context.theme.colors.primary,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  draftDiscarded
                      ? l10n.knowledgeCaptureDraftCleared
                      : l10n.knowledgeCaptureDraftRecovered,
                  style: context.bodyCaptionStyle,
                ),
              ),
              Semantics(
                button: true,
                enabled: !draftDiscarded,
                label: draftDiscarded
                    ? l10n.knowledgeCaptureDraftCleared
                    : l10n.knowledgeCaptureDraftDiscard,
                child: AppTappable(
                  onPress: draftDiscarded ? null : onDiscardDraft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppControlHeights.touchTarget,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          draftDiscarded
                              ? l10n.knowledgeCaptureDraftCleared
                              : l10n.knowledgeCaptureDraftDiscard,
                          style: context.mediumLabelStyle.copyWith(
                            color: draftDiscarded
                                ? context.theme.colors.mutedForeground
                                : context.theme.colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= Breakpoints.dialogWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _versionPanel(
                      context,
                      label: l10n.knowledgeCaptureOriginalVersion,
                      child: _originalPanel(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    child: _versionPanel(
                      context,
                      label: l10n.knowledgeCaptureOrganizedVersion,
                      child: _organizedPanel(context),
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      onPress: () =>
                          setState(() => _showOriginal = !_showOriginal),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                if (_showOriginal)
                  _originalPanel(context)
                else
                  _organizedPanel(context),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _versionPanel(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.labelStyle),
        const SizedBox(height: AppSpacing.s8),
        child,
      ],
    );
  }

  Widget _originalPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: AppPageRhythm.densePadding,
      decoration: BoxDecoration(
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
    );
  }

  Widget _organizedPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
    );
  }
}
