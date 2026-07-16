part of '_decision_writer.dart';

class _OptionDraft {
  _OptionDraft({String label = '', String rationale = ''})
    : labelCtrl = TextEditingController(text: label),
      rationaleCtrl = TextEditingController(text: rationale);
  final TextEditingController labelCtrl;
  final TextEditingController rationaleCtrl;
  void dispose() {
    labelCtrl.dispose();
    rationaleCtrl.dispose();
  }
}

class _OptionEditorTile extends StatelessWidget {
  const _OptionEditorTile({
    required this.draft,
    required this.index,
    required this.selected,
    required this.onSelect,
    this.onRemove,
  });
  final _OptionDraft draft;
  final int index;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: SoftCard(
        level: SoftCardLevel.flat,
        borderless: !selected,
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FRadio(
                  value: selected,
                  onChange: draft.labelCtrl.text.trim().isEmpty
                      ? null
                      : (_) => onSelect(),
                  semanticsLabel: AppLocalizations.of(
                    context,
                  ).knowledgeDecisionOptionLabelHint(index + 1),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: draft.labelCtrl,
                    ),
                    hint: AppLocalizations.of(
                      context,
                    ).knowledgeDecisionOptionLabelHint(index + 1),
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: AppSpacing.s4),
                  FButton.icon(
                    variant: FButtonVariant.outline,
                    onPress: onRemove,
                    child: const Icon(FLucideIcons.x, size: AppIconSizes.xs),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            FTextField(
              control: FTextFieldControl.managed(
                controller: draft.rationaleCtrl,
              ),
              hint: AppLocalizations.of(
                context,
              ).knowledgeDecisionOptionRationaleHint,
              maxLines: 2,
              minLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
