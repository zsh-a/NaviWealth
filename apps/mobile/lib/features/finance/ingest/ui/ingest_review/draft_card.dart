part of '../ingest_review_page.dart';

class _DraftMasterRow extends StatelessWidget {
  const _DraftMasterRow({
    required this.draft,
    required this.selected,
    required this.selectable,
    required this.focused,
    required this.busy,
    required this.pendingFinalize,
    required this.recoveryUnavailable,
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
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final parsed = draft.parsed;
    return Semantics(
      key: ValueKey('ingest-master-${draft.draftId}'),
      container: true,
      button: true,
      selected: focused,
      enabled: !busy,
      onTap: busy ? null : onFocus,
      child: FTappable(
        onPress: busy ? null : onFocus,
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s10,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.muted : colors.background,
            border: Border.all(
              color: focused ? colors.primary : colors.border,
              width: focused ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Checkbox.adaptive(
                value: selected,
                semanticLabel: parsed.description,
                onChanged: selectable && !busy
                    ? (value) => onSelectionChanged(value ?? false)
                    : null,
              ),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      parsed.description,
                      style: context.labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Row(
                      children: [
                        if (pendingFinalize || recoveryUnavailable) ...[
                          Icon(
                            FLucideIcons.triangleAlert,
                            size: AppIconSizes.xs,
                            color: colors.destructive,
                          ),
                          const SizedBox(width: AppSpacing.s4),
                        ],
                        _VerdictIndicator(verdict: draft.verdict),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              MoneyText(
                amount: parsed.amountMinor.abs() / 100.0,
                currencyCode: parsed.currency,
                style: context.strongLabelStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.selected,
    required this.selectable,
    required this.focused,
    required this.busy,
    required this.pendingFinalize,
    required this.recoveryUnavailable,
    this.showSelection = true,
    required this.onConfirm,
    required this.onSkip,
    required this.onEdit,
    required this.onTransfer,
    required this.onTrade,
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
  final bool showSelection;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;
  final VoidCallback onEdit;
  final VoidCallback onTransfer;
  final VoidCallback onTrade;
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
      child: SoftCard.raised(
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
                if (showSelection) ...[
                  Checkbox.adaptive(
                    value: selected,
                    onChanged: selectable && !busy
                        ? (value) => onSelectionChanged(value ?? false)
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.s4),
                ],
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
                  icon: switch (p.kind) {
                    IngestTransactionKind.income => FLucideIcons.trendingUp,
                    IngestTransactionKind.expense => FLucideIcons.trendingDown,
                    IngestTransactionKind.transfer =>
                      FLucideIcons.arrowRightLeft,
                    IngestTransactionKind.trade =>
                      FLucideIcons.chartCandlestick,
                  },
                  label: switch (p.kind) {
                    IngestTransactionKind.income => l10n.ingestKindIncome,
                    IngestTransactionKind.expense => l10n.ingestKindExpense,
                    IngestTransactionKind.transfer => l10n.ingestKindTransfer,
                    IngestTransactionKind.trade => l10n.ingestKindTrade,
                  },
                ),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppActionButton(
                    variant: FButtonVariant.ghost,
                    onPress: busy ? null : onEdit,
                    child: Text(l10n.ingestEditDraft),
                  ),
                  const SizedBox(height: AppSpacing.s6),
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
                          onPress: busy
                              ? null
                              : p.kind == IngestTransactionKind.transfer
                              ? onTransfer
                              : p.kind == IngestTransactionKind.trade
                              ? onTrade
                              : onConfirm,
                          child: Flexible(
                            child: Text(
                              p.kind == IngestTransactionKind.transfer
                                  ? l10n.ingestRecordTransfer
                                  : p.kind == IngestTransactionKind.trade
                                  ? l10n.ingestRecordTrade
                                  : l10n.ingestConfirm,
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
