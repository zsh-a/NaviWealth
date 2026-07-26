part of 'activity_entry_detail_page.dart';

class _HeroAmountCard extends StatelessWidget {
  const _HeroAmountCard({
    required this.entry,
    required this.accountsById,
    required this.formatters,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final headline = _headlinePosting(entry.postings, accountsById);
    final dateLine = formatters.dateTime(entry.entry.date);
    final title = entry.entry.narration.isEmpty ? '—' : entry.entry.narration;
    final payee = entry.entry.payee;
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    final tint = _tintForKind(classification.kind, colors, status);
    return SoftCard.hero(
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _KindGlyph(kind: classification.kind, tint: tint),
              const SizedBox(width: AppSpacing.s12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _KindLabel(
                    label: entryKindLabel(
                      AppLocalizations.of(context),
                      classification.kind,
                    ),
                    tint: tint,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Flexible(
                child: Text(
                  dateLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.captionStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (headline != null)
            SignedMoneyText(
              amount: headline.units,
              unit: headline.unit,
              formatters: formatters,
              style: TypographyTokens.displayLarge.copyWith(height: 1.05),
            ),
          const SizedBox(height: AppSpacing.s12),
          Text(title, style: context.titleLabelStyle.copyWith(height: 1.22)),
          if (payee != null && payee.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(payee, style: context.bodyCaptionStyle.copyWith(height: 1.35)),
          ],
        ],
      ),
    );
  }
}

class _KindGlyph extends StatelessWidget {
  const _KindGlyph({required this.kind, required this.tint});

  final EntryKind kind;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: AppOpacity.light),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(_iconForKind(kind), color: tint, size: AppIconSizes.sm),
    );
  }
}

class _KindLabel extends StatelessWidget {
  const _KindLabel({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.microLabelStyle.copyWith(color: colors.foreground),
      ),
    );
  }
}
