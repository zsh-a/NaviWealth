part of '../ingest_review_page.dart';

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.selected,
    required this.selectable,
    required this.focused,
    required this.busy,
    required this.pendingFinalize,
    required this.recoveryUnavailable,
    required this.onConfirm,
    required this.onSkip,
    required this.onFinalize,
    required this.onSelectionChanged,
    required this.onFocus,
  });

  final IngestDraft draft;
  final bool selected;
  final bool selectable;
  final bool focused;
  final bool busy;
  final bool pendingFinalize;
  final bool recoveryUnavailable;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;
  final VoidCallback? onFinalize;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = draft.parsed;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onFocus,
      child: SoftCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.s12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox.adaptive(
                  value: selected,
                  onChanged: selectable && !busy
                      ? (value) => onSelectionChanged(value ?? false)
                      : null,
                ),
                const SizedBox(width: AppSpacing.s4),
                Expanded(
                  child: Text(
                    p.description,
                    style: context.labelStyle.copyWith(
                      height: 1.25,
                      color: focused ? context.theme.colors.primary : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                MoneyText(
                  amount: p.amountMinor.abs() / 100.0,
                  currencyCode: p.currency,
                  style: context.strongLabelStyle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DraftMetaChip(
                  icon: FLucideIcons.calendar,
                  label: _ymd(p.occurredAt),
                ),
                _DraftMetaChip(
                  icon: FLucideIcons.tags,
                  label: p.categoryHint ?? l10n.ingestUncategorized,
                ),
                _DraftMetaChip(
                  icon: _sourceIcon(draft.sourceKind),
                  label: _draftSourceLabel(l10n, draft),
                ),
                _DraftMetaChip(
                  icon: FLucideIcons.sparkles,
                  label: l10n.ingestDraftConfidence(
                    (draft.confidence * 100).round(),
                  ),
                ),
                _VerdictIndicator(verdict: draft.verdict),
              ],
            ),
            const SizedBox(height: AppSpacing.s10),
            if (pendingFinalize || recoveryUnavailable) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    FLucideIcons.triangleAlert,
                    size: AppIconSizes.sm,
                    color: context.theme.colors.destructive,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      recoveryUnavailable
                          ? l10n.ingestRecoveryUnavailableHint
                          : l10n.ingestNeedsReviewHint,
                      style: context.bodyCaptionStyle,
                    ),
                  ),
                ],
              ),
              if (!recoveryUnavailable) ...[
                const SizedBox(height: AppSpacing.s10),
                AppActionButton(
                  variant: FButtonVariant.primary,
                  onPress: busy ? null : onFinalize,
                  child: Text(l10n.ingestResolveAction),
                ),
              ],
            ] else
              Row(
                children: [
                  Expanded(
                    child: AppActionButton(
                      variant: FButtonVariant.outline,
                      onPress: busy ? null : onSkip,
                      child: Flexible(
                        child: Text(
                          l10n.ingestSkip,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: AppActionButton(
                      variant: FButtonVariant.primary,
                      onPress: busy ? null : onConfirm,
                      child: Flexible(
                        child: Text(
                          l10n.ingestConfirm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static IconData _sourceIcon(IngestSourceKind kind) {
    return switch (kind) {
      IngestSourceKind.csv => FLucideIcons.fileSpreadsheet,
      IngestSourceKind.pasteText => FLucideIcons.clipboard,
      IngestSourceKind.receiptImage => FLucideIcons.image,
      IngestSourceKind.statementPdf => FLucideIcons.fileText,
      IngestSourceKind.email => FLucideIcons.mail,
    };
  }

  static String _draftSourceLabel(AppLocalizations l10n, IngestDraft draft) {
    final origin = draft.originLabel?.trim();
    if (origin != null && origin.isNotEmpty && origin != 'paste') {
      return origin;
    }
    return switch (draft.sourceKind) {
      IngestSourceKind.csv => l10n.ingestSourceCsv,
      IngestSourceKind.pasteText => l10n.ingestSourcePaste,
      IngestSourceKind.receiptImage => l10n.ingestSourceImage,
      IngestSourceKind.statementPdf => l10n.ingestSourcePdf,
      IngestSourceKind.email => l10n.ingestSourceEmail,
    };
  }

  static String _ymd(DateTime d) {
    final u = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}';
  }
}

class _DraftMetaChip extends StatelessWidget {
  const _DraftMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
          const SizedBox(width: AppSpacing.s4),
          Text(
            label,
            style: context.microLabelStyle.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictIndicator extends StatelessWidget {
  const _VerdictIndicator({required this.verdict});

  final DedupVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, state) = switch (verdict) {
      DedupVerdict.newTxn => (l10n.ingestVerdictNew, AiPillState.neutral),
      DedupVerdict.likelyDuplicate => (
        l10n.ingestVerdictLikely,
        AiPillState.selected,
      ),
      DedupVerdict.duplicate => (
        l10n.ingestVerdictDuplicate,
        AiPillState.error,
      ),
    };
    return AiPill(label: label, state: state);
  }
}
