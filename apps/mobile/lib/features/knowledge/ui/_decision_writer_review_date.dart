part of '_decision_writer.dart';

Future<DateTime?> _pickReviewDate(BuildContext context) async {
  final now = DateTime.now();
  // Minimal date picker — Forui has no native calendar widget; we offer common
  // shortcuts plus a strict YYYY-MM-DD custom input without adding a dependency.
  return showAppFormSheet<DateTime>(
    context: context,
    builder: (sheetContext) => _ReviewDateSheet(now: now),
  );
}

class _ReviewDateSheet extends StatefulWidget {
  const _ReviewDateSheet({required this.now});
  final DateTime now;

  @override
  State<_ReviewDateSheet> createState() => _ReviewDateSheetState();
}

class _ReviewDateSheetState extends State<_ReviewDateSheet> {
  final _customCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseCustomDate(BuildContext context) {
    final raw = _customCtrl.text.trim();
    final l10n = AppLocalizations.of(context);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) {
      setState(() => _error = l10n.knowledgeDecisionReviewDateInvalid);
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      setState(() => _error = l10n.knowledgeDecisionReviewDateInvalid);
      return null;
    }
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    if (parsed.isBefore(today)) {
      setState(() => _error = l10n.knowledgeDecisionReviewDatePast);
      return null;
    }
    setState(() => _error = null);
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    Widget choice(int days, String label) => KnowledgeSelectableRow(
      label: label,
      selected: false,
      mode: KnowledgeSelectionMode.radio,
      onPress: () =>
          Navigator.of(context).pop(widget.now.add(Duration(days: days))),
    );
    return AppSheet(
      title: l10n.knowledgeDecisionReviewDateTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeWriterSection(
            title: l10n.knowledgeDecisionReviewDateTitle,
            children: [
              choice(30, l10n.knowledgeDecisionReviewDateInDays(30)),
              choice(90, l10n.knowledgeDecisionReviewDateInDays(90)),
              choice(180, l10n.knowledgeDecisionReviewDateInDays(180)),
              choice(365, l10n.knowledgeDecisionReviewDateInOneYear),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeDecisionReviewDateCustomLabel,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _customCtrl),
                hint: l10n.knowledgeDecisionReviewDateCustomHint,
                textInputAction: TextInputAction.done,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: context.captionStyle.copyWith(
                    color: colors.destructive,
                  ),
                ),
              FButton(
                onPress: () {
                  final parsed = _parseCustomDate(context);
                  if (parsed != null) Navigator.of(context).pop(parsed);
                },
                child: Text(l10n.knowledgeDecisionReviewDateCustomApply),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
