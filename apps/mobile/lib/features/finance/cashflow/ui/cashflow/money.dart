part of '../cashflow_page.dart';

class _DualMoneyText extends StatefulWidget {
  const _DualMoneyText({
    required this.money,
    required this.formatter,
    required this.style,
    this.signed = false,
  });

  final _MoneyBreakdown money;
  final AppFormatters formatter;
  final TextStyle style;
  final bool signed;

  @override
  State<_DualMoneyText> createState() => _DualMoneyTextState();
}

class _DualMoneyTextState extends State<_DualMoneyText> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = _showOriginal
        ? widget.money.formatOriginal(widget.formatter, signed: widget.signed)
        : widget.money.formatBase(widget.formatter, signed: widget.signed);
    final value = Text(
      text,
      style: widget.style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final hasAlternateCurrency = widget.money.originals.keys.any(
      (currency) => currency != widget.money.baseCurrency,
    );
    if (!hasAlternateCurrency) return value;

    final actionLabel = _showOriginal
        ? l10n.cashFlowShowBaseCurrency
        : l10n.cashFlowShowOriginalCurrencies;
    return Tooltip(
      message: actionLabel,
      child: AppTappable(
        semanticsLabel: '$text. $actionLabel',
        onPress: () => setState(() => _showOriginal = !_showOriginal),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppControlHeights.touchTarget,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: value,
          ),
        ),
      ),
    );
  }
}

class _MoneyBreakdown {
  const _MoneyBreakdown({
    required this.baseAmount,
    required this.baseCurrency,
    required this.originals,
  });

  final Decimal baseAmount;
  final String baseCurrency;
  final Map<String, Decimal> originals;

  String formatBase(AppFormatters formatter, {required bool signed}) {
    if (signed) {
      return formatter.signedMoney(baseAmount, unit: baseCurrency);
    }
    return formatter.currency(baseAmount.abs(), code: baseCurrency);
  }

  String formatOriginal(AppFormatters formatter, {required bool signed}) {
    if (originals.isEmpty) return formatBase(formatter, signed: signed);
    final entries = originals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map(
          (entry) => signed
              ? formatter.signedMoney(entry.value, unit: entry.key)
              : formatter.currency(entry.value.abs(), code: entry.key),
        )
        .join(' / ');
  }
}
