part of '../ingest_review_page.dart';

class _DuplicateComparison extends ConsumerWidget {
  const _DuplicateComparison({required this.draft});

  final IngestDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final target = draft.dedupTargetEntryId;
    if (target == null) {
      return Text(l10n.ingestMatchUnavailable, style: context.bodyCaptionStyle);
    }
    return ref
        .watch(
          ingestDuplicateMatchProvider((
            targetId: target,
            against: draft.parsed,
          )),
        )
        .whenOrLoading(
          context: context,
          loading: () =>
              Text(l10n.ingestMatchLoading, style: context.bodyCaptionStyle),
          error: (_, _) => Text(
            l10n.ingestMatchUnavailable,
            style: context.bodyCaptionStyle,
          ),
          data: (match) {
            if (match == null) {
              return Text(
                l10n.ingestMatchUnavailable,
                style: context.bodyCaptionStyle,
              );
            }
            final parsed = match.parsed;
            final imported = draft.parsed;
            final amountDiffers =
                imported.amountMinor != parsed.amountMinor ||
                imported.currency.toUpperCase() !=
                    parsed.currency.toUpperCase();
            final reason = switch (match.reason) {
              DedupMatchReason.sourceIdentity => l10n.ingestMatchReasonIdentity,
              DedupMatchReason.exactDetails => l10n.ingestMatchReasonExact,
              DedupMatchReason.merchantDescription =>
                l10n.ingestMatchReasonMerchant,
              DedupMatchReason.dateDrift => l10n.ingestMatchReasonDate,
              null => l10n.ingestMatchUnavailable,
            };
            return Column(
              key: ValueKey('ingest-match-${draft.draftId}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(reason, style: context.labelStyle),
                if (match.reason == DedupMatchReason.sourceIdentity &&
                    amountDiffers)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.ingestMatchAmountConflict,
                        style: context.bodyCaptionStyle.copyWith(
                          color: context.appTheme.status.warning.fg,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.s12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.ingestComparisonImported,
                        style: context.labelStyle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: Text(
                        match.isDraft
                            ? l10n.ingestMatchedDraft
                            : l10n.ingestMatchedLedger,
                        style: context.labelStyle,
                      ),
                    ),
                  ],
                ),
                _ComparisonField(
                  label: l10n.ingestEditAmount,
                  imported:
                      '${imported.currency} ${formatMinorUnitAmount(imported.amountMinor)}',
                  matched:
                      '${parsed.currency} ${formatMinorUnitAmount(parsed.amountMinor)}',
                  differs: amountDiffers,
                ),
                _ComparisonField(
                  label: l10n.ingestEditDate,
                  imported: _comparisonStamp(imported),
                  matched: _comparisonStamp(parsed),
                  differs:
                      imported.occurredAt != parsed.occurredAt ||
                      imported.dateHasTime != parsed.dateHasTime,
                ),
                _ComparisonField(
                  label: l10n.ingestEditDescription,
                  imported: imported.description,
                  matched: parsed.description,
                  differs: imported.description != parsed.description,
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l10n.ingestCompareBeforeRecording,
                  style: context.bodyCaptionStyle,
                ),
                if (!match.isDraft) ...[
                  const SizedBox(height: AppSpacing.s8),
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () =>
                        context.push(FinanceRoutes.activityEntry(target)),
                    child: Text(l10n.ingestViewOriginal),
                  ),
                ],
              ],
            );
          },
        );
  }
}

class _ComparisonField extends StatelessWidget {
  const _ComparisonField({
    required this.label,
    required this.imported,
    required this.matched,
    required this.differs,
  });

  final String label;
  final String imported;
  final String matched;
  final bool differs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            differs ? '$label · ${l10n.ingestComparisonDifferent}' : label,
            style: context.bodyCaptionStyle.copyWith(
              color: differs ? context.appTheme.status.warning.fg : null,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(imported, style: context.bodyCaptionStyle)),
              const SizedBox(width: AppSpacing.s12),
              Expanded(child: Text(matched, style: context.bodyCaptionStyle)),
            ],
          ),
        ],
      ),
    );
  }
}

String _comparisonStamp(ParsedTransaction parsed) {
  final date = _DraftCard._ymd(parsed.occurredAt);
  if (!parsed.dateHasTime) return date;
  final local = parsed.occurredAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '$date ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
