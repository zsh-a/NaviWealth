part of 'tool_invocation_renderers.dart';

// ===========================================================================
// Domain renderers for Snapshot/Analytical read-model tools.
// Calm Intelligence: surface tone, no glow, type-first layout. Each view
// degrades gracefully (empty / off-shape payloads) and never throws.
// ===========================================================================

// ---------------------------------------------------------------------------
// get_recurring_patterns → subscription cards with cadence chips.
// Payload shape: { patterns: [{id, merchant_key, cadence, currency,
//   median_amount_minor (string), occurrences (int), last_seen_at}],
//   count, source, note }
// ---------------------------------------------------------------------------

class RecurringPatternsView extends StatelessWidget {
  const RecurringPatternsView({super.key, required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final m = _asMap(output);
    final l10n = AppLocalizations.of(context);
    final raw = _asList(m?['patterns']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return ToolResultSurface(
        child: _EmptyHint(text: l10n.aiToolRecurringPatternsEmpty),
      );
    }
    final visible = raw.take(_kMaxVisibleRows).toList();
    final fmt = NumberFormat.decimalPattern();
    return ToolResultSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: _patternRow(context, entry, fmt),
            ),
          if (raw.length > visible.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                l10n.aiToolMoreItems(raw.length - visible.length),
                style: context.microCaptionStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _patternRow(BuildContext context, Object? entry, NumberFormat fmt) {
    final mp = _asMap(entry);
    if (mp == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final merchant = _asString(mp['merchant_key']) ?? '(unknown)';
    final cadence = _asString(mp['cadence']) ?? '?';
    final currency = _asString(mp['currency']) ?? '';
    final medianMinor =
        int.tryParse(_asString(mp['median_amount_minor']) ?? '0') ?? 0;
    final occ = (mp['occurrences'] is int)
        ? mp['occurrences']! as int
        : int.tryParse(_asString(mp['occurrences']) ?? '0') ?? 0;
    final lastSeen = _asDate(mp['last_seen_at']);
    final cadenceLabel = switch (cadence) {
      'monthly' => l10n.aiToolCadenceMonthly,
      'weekly' => l10n.aiToolCadenceWeekly,
      _ => cadence,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(
          alpha: AppOpacity.disabled,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(merchant, style: context.mediumLabelStyle),
                const SizedBox(height: AppSpacing.s2),
                Row(
                  children: [
                    _miniChip(context, cadenceLabel),
                    const SizedBox(width: AppSpacing.s6),
                    Text(
                      lastSeen == null
                          ? l10n.aiToolOccurrences(occ)
                          : l10n.aiToolOccurrencesRecent(
                              occ,
                              _displayDate(lastSeen),
                            ),
                      style: context.microCaptionStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            '${fmt.format(medianMinor.abs() / 100.0)} $currency',
            style: context.theme.typography.body.sm.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _miniChip(BuildContext context, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s6,
      vertical: AppSpacing.hairline,
    ),
    decoration: BoxDecoration(
      color: context.theme.colors.border.withValues(alpha: AppOpacity.light),
      borderRadius: BorderRadius.circular(AppRadius.full),
    ),
    child: Text(label, style: context.microCaptionStyle),
  );
}

// ---------------------------------------------------------------------------
// get_subscription_changes → price-diff bars (↑/↓).
// Payload shape: { changes: [{id, merchant_key, cadence, currency,
//   prev_amount_minor (string), new_amount_minor (string),
//   delta_ratio (double), since (iso datetime)}], count, source, note }
// ---------------------------------------------------------------------------

class SubscriptionChangesView extends StatelessWidget {
  const SubscriptionChangesView({super.key, required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final m = _asMap(output);
    final l10n = AppLocalizations.of(context);
    final raw = _asList(m?['changes']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return ToolResultSurface(
        child: _EmptyHint(text: l10n.aiToolSubscriptionChangesEmpty),
      );
    }
    final visible = raw.take(_kMaxVisibleRows).toList();
    return ToolResultSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: _changeRow(context, entry),
            ),
          if (raw.length > visible.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                l10n.aiToolMoreItems(raw.length - visible.length),
                style: context.microCaptionStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _changeRow(BuildContext context, Object? entry) {
    final mp = _asMap(entry);
    if (mp == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final merchant = _asString(mp['merchant_key']) ?? '(unknown)';
    final currency = _asString(mp['currency']) ?? '';
    final prev = int.tryParse(_asString(mp['prev_amount_minor']) ?? '') ?? 0;
    final next = int.tryParse(_asString(mp['new_amount_minor']) ?? '') ?? 0;
    final delta = _asDouble(mp['delta_ratio']) ?? 0.0;
    final since = _asDate(mp['since']);
    final up = next.abs() > prev.abs();
    final accent = up
        ? context.theme.colors.destructive
        : context.theme.colors.primary;
    final fmt = NumberFormat.decimalPattern();
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: AppOpacity.faint),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: accent.withValues(alpha: AppOpacity.muted)),
      ),
      child: Row(
        children: [
          Icon(
            up ? FLucideIcons.trendingUp : FLucideIcons.trendingDown,
            size: AppIconSizes.h18,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(merchant, style: context.mediumLabelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  '${fmt.format(prev.abs() / 100.0)} → ${fmt.format(next.abs() / 100.0)} $currency'
                  '${since != null ? l10n.aiToolSinceDate(_displayDate(since)) : ''}',
                  style: context.microCaptionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            formatters.signedPercent(delta, decimalDigits: 1),
            style: context.labelStyle.copyWith(
              color: accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// get_refund_links → original ↔ refund pair cards.
// Payload shape: { links: [{id, original_txn_id, refund_txn_id,
//   amount_minor (string), currency, payload}], count, source, note }
// ---------------------------------------------------------------------------

class RefundLinksView extends StatelessWidget {
  const RefundLinksView({super.key, required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final m = _asMap(output);
    final l10n = AppLocalizations.of(context);
    final raw = _asList(m?['links']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return ToolResultSurface(
        child: _EmptyHint(text: l10n.aiToolRefundLinksEmpty),
      );
    }
    final visible = raw.take(_kMaxVisibleRows).toList();
    final fmt = NumberFormat.decimalPattern();
    return ToolResultSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: _pairRow(context, entry, fmt),
            ),
          if (raw.length > visible.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                l10n.aiToolMoreItems(raw.length - visible.length),
                style: context.microCaptionStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _pairRow(BuildContext context, Object? entry, NumberFormat fmt) {
    final mp = _asMap(entry);
    if (mp == null) return const SizedBox.shrink();
    final origin = _asString(mp['original_txn_id']) ?? '?';
    final refund = _asString(mp['refund_txn_id']) ?? '?';
    final amountMinor = int.tryParse(_asString(mp['amount_minor']) ?? '') ?? 0;
    final currency = _asString(mp['currency']) ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(
          alpha: AppOpacity.disabled,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      FLucideIcons.arrowDownLeft,
                      size: AppIconSizes.xs,
                      color: context.theme.colors.mutedForeground,
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    Expanded(
                      child: Text(
                        origin,
                        style: context.bodyCaptionStyle.copyWith(
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Row(
                  children: [
                    Icon(
                      FLucideIcons.arrowUpRight,
                      size: AppIconSizes.xs,
                      color: context.theme.colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    Expanded(
                      child: Text(
                        refund,
                        style: context.theme.typography.body.sm.copyWith(
                          fontFamily: 'monospace',
                          color: context.theme.colors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            '${fmt.format(amountMinor.abs() / 100.0)} $currency',
            style: context.theme.typography.body.sm.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Text(text, style: context.captionStyle),
    );
  }
}
