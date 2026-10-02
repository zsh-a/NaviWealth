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
        .when(
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
            return Column(
              key: ValueKey('ingest-match-${draft.draftId}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_comparisonStamp(draft.parsed)} · ${draft.parsed.currency} ${formatMinorUnitAmount(draft.parsed.amountMinor)}',
                  style: context.bodyCaptionStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  match.isDraft
                      ? l10n.ingestMatchedDraft
                      : l10n.ingestMatchedLedger,
                  style: context.labelStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(parsed.description, style: context.bodyCaptionStyle),
                Text(
                  '${_comparisonStamp(parsed)} · ${parsed.currency} ${formatMinorUnitAmount(parsed.amountMinor)}',
                  style: context.bodyCaptionStyle,
                ),
                Text(
                  l10n.ingestCompareBeforeRecording,
                  style: context.bodyCaptionStyle,
                ),
              ],
            );
          },
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
