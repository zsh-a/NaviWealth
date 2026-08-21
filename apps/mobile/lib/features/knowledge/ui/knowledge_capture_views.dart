part of 'knowledge_capture_sheet.dart';

class _ComposeBody extends StatelessWidget {
  const _ComposeBody({
    required this.titleController,
    required this.bodyController,
    required this.bodyFocusNode,
  });
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final FocusNode bodyFocusNode;

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
      ],
    );
  }
}
