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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.knowledgeCaptureTypeLabel, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s6),
        AppAdaptiveChoice<CaptureKind?>(
          title: l10n.knowledgeCaptureTypeLabel,
          subtitle: l10n.knowledgeCaptureKindAutoDescription,
          options: const <CaptureKind?>[null, ...CaptureKind.values],
          value: selectedKind,
          labelOf: (kind) => kind == null
              ? l10n.knowledgeCaptureKindAuto
              : _captureKindShortLabel(l10n, kind),
          descriptionOf: (kind) => kind == null
              ? l10n.knowledgeCaptureKindAutoDescription
              : _captureKindDescription(l10n, kind),
          iconOf: _captureKindIcon,
          onChanged: onChanged,
        ),
      ],
    );
  }
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

String _captureKindDescription(AppLocalizations l10n, CaptureKind kind) {
  return switch (kind) {
    CaptureKind.note => l10n.knowledgeCaptureKindNoteDescription,
    CaptureKind.routine => l10n.knowledgeCaptureKindRoutineDescription,
    CaptureKind.decision => l10n.knowledgeCaptureKindDecisionDescription,
    CaptureKind.principle => l10n.knowledgeCaptureKindPrincipleDescription,
    CaptureKind.assumption => l10n.knowledgeCaptureKindAssumptionDescription,
    CaptureKind.concept => l10n.knowledgeCaptureKindConceptDescription,
    CaptureKind.experiment => l10n.knowledgeCaptureKindExperimentDescription,
  };
}

IconData _captureKindIcon(CaptureKind? kind) => switch (kind) {
  null => FLucideIcons.sparkles,
  CaptureKind.note => FLucideIcons.fileText,
  CaptureKind.routine => FLucideIcons.calendarClock,
  CaptureKind.decision => FLucideIcons.gitBranch,
  CaptureKind.principle => FLucideIcons.badgeCheck,
  CaptureKind.assumption => FLucideIcons.lightbulb,
  CaptureKind.concept => FLucideIcons.folderTree,
  CaptureKind.experiment => FLucideIcons.flaskConical,
};
