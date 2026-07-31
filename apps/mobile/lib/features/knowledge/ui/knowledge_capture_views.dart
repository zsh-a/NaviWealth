part of 'knowledge_capture_sheet.dart';

class _ComposeBody extends StatelessWidget {
  const _ComposeBody({
    required this.titleController,
    required this.bodyController,
    required this.selectedKind,
    required this.onKindChanged,
  });
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final CaptureKind? selectedKind;
  final ValueChanged<CaptureKind?> onKindChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeWriterSection(
      title: l10n.knowledgeCaptureTitle,
      children: [
        _CaptureKindPicker(
          selectedKind: selectedKind,
          onChanged: onKindChanged,
        ),
        FTextField(
          control: FTextFieldControl.managed(controller: titleController),
          label: Text(l10n.knowledgeCaptureTitleField),
          hint: l10n.knowledgeCaptureTitleHint,
        ),
        FTextField(
          control: FTextFieldControl.managed(controller: bodyController),
          label: Text(l10n.knowledgeCaptureBodyField),
          hint: l10n.knowledgeCaptureBodyHint,
          minLines: 4,
          maxLines: 8,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: SpeechInputButton(controller: bodyController),
        ),
      ],
    );
  }
}

class _CaptureKindPicker extends StatelessWidget {
  const _CaptureKindPicker({
    required this.selectedKind,
    required this.onChanged,
  });

  final CaptureKind? selectedKind;
  final ValueChanged<CaptureKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <_CaptureKindOption>[
      _CaptureKindOption(null, l10n.knowledgeCaptureKindAuto),
      for (final kind in CaptureKind.values)
        _CaptureKindOption(kind, _captureKindShortLabel(l10n, kind)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.knowledgeCaptureTypeLabel, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                _CaptureKindChip(
                  label: options[i].label,
                  selected: options[i].kind == selectedKind,
                  onTap: () => onChanged(options[i].kind),
                ),
                if (i != options.length - 1)
                  const SizedBox(width: AppSpacing.s6),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CaptureKindChip extends StatelessWidget {
  const _CaptureKindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFilterChip(label: label, active: selected, onPress: onTap);
  }
}

class _CaptureKindOption {
  const _CaptureKindOption(this.kind, this.label);

  final CaptureKind? kind;
  final String label;
}

String _captureKindShortLabel(AppLocalizations l10n, CaptureKind kind) {
  return switch (kind) {
    CaptureKind.note => l10n.knowledgeCaptureKindNote,
    CaptureKind.routine => l10n.knowledgeCaptureKindRoutine,
    CaptureKind.decision => l10n.knowledgeCaptureKindDecision,
    CaptureKind.principle => l10n.knowledgeCaptureKindPrinciple,
    CaptureKind.assumption => l10n.knowledgeCaptureKindAssumption,
    CaptureKind.concept => l10n.knowledgeCaptureKindConcept,
    CaptureKind.experiment => l10n.knowledgeCaptureKindExperiment,
  };
}
