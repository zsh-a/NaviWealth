import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../core/format/formatters.dart';
import '../../domain/values/money.dart';
import '../theme/semantic_colors.dart';
import '../tokens/typography_tokens.dart';
import 'amount_privacy_placeholder.dart';
import 'amount_privacy_scope.dart';

/// How much horizontal space the symbol should take.
enum MoneySymbolStyle {
  /// `¥`, `$`, `€` (compact glyph). Default.
  symbol,

  /// `CNY`, `USD`, `EUR` (always 3 letters, useful in tables).
  isoCode,

  /// Don't render any symbol.
  none,
}

/// Renders a monetary amount with consistent typography (lining tabular
/// figures), thousands grouping, and a configurable currency symbol.
///
/// Direction-tinted "delta" amounts should use [DeltaText] instead — this
/// widget is brightness/scheme aware but does NOT colour by sign.
class MoneyText extends StatelessWidget {
  // Static cache for NumberFormat instances — constructing them is
  // expensive and the same locale+currency+style combo is reused
  // thousands of times (especially during AnimatedMoneyText tweens
  // at 120fps). Key is a compact string encoding of the parameters.
  static final Map<String, NumberFormat> _formatCache = {};

  static NumberFormat _cachedFormat({
    required String locale,
    required String currencyCode,
    required MoneySymbolStyle symbolStyle,
    required bool compact,
    required int? fractionDigits,
    String? symbol,
  }) {
    final effectiveSymbol = symbol ?? AppFormatters.currencyGlyph(currencyCode);
    final key =
        '$locale|$currencyCode|${symbolStyle.index}|$compact|$fractionDigits|$effectiveSymbol';
    return _formatCache.putIfAbsent(key, () {
      switch (symbolStyle) {
        case MoneySymbolStyle.symbol:
          return compact
              ? NumberFormat.compactCurrency(
                  locale: locale,
                  name: currencyCode,
                  symbol: effectiveSymbol,
                )
              : NumberFormat.currency(
                  locale: locale,
                  name: currencyCode,
                  symbol: effectiveSymbol,
                  decimalDigits: fractionDigits,
                );
        case MoneySymbolStyle.isoCode:
          return compact
              ? NumberFormat.compactCurrency(
                  locale: locale,
                  name: currencyCode,
                  symbol: '$currencyCode ',
                )
              : NumberFormat.currency(
                  locale: locale,
                  name: currencyCode,
                  symbol: '$currencyCode ',
                  decimalDigits: fractionDigits,
                );
        case MoneySymbolStyle.none:
          return compact
              ? NumberFormat.compact(locale: locale)
              : NumberFormat.decimalPatternDigits(
                  locale: locale,
                  decimalDigits: fractionDigits ?? 2,
                );
      }
    });
  }

  const MoneyText({
    super.key,
    required this.amount,
    this.currencyCode = 'CNY',
    this.symbol,
    this.symbolStyle = MoneySymbolStyle.symbol,
    this.fractionDigits,
    this.style,
    this.color,
    this.locale,
    this.textAlign,
    this.compact = false,
    this.showSign = false,
    this.semanticsLabel,
  });

  /// Amount in the major unit (e.g. `1234.5` = ¥1,234.50). Accepts `num` so
  /// callers can pass either `int` or `double`. Pass via `Decimal.toDouble()`
  /// at the boundary for now; a `Decimal`-typed overload can come later
  /// without churning callers.
  final num? amount;

  /// ISO 4217 currency code (drives default symbol + decimal places).
  final String currencyCode;

  /// Override the symbol glyph (e.g. `'US$'`). Defaults to the locale's
  /// symbol for [currencyCode].
  final String? symbol;

  final MoneySymbolStyle symbolStyle;

  /// Override decimals. If null, uses the currency's default (most fiat = 2,
  /// JPY = 0, etc.).
  final int? fractionDigits;

  /// Text style override. Defaults to [TypographyTokens.numericBody].
  final TextStyle? style;

  final Color? color;

  /// Locale for grouping/decimal separator. Defaults to current app locale.
  final String? locale;

  final TextAlign? textAlign;

  /// Render `1.2K`, `3.4M`, `5.6B` style (useful in tight chart axis labels).
  final bool compact;

  /// Always render the leading `+` for positive values. Useful next to a
  /// delta. Negative numbers always show `-`.
  final bool showSign;

  /// Override the screen-reader label. Defaults to a spoken
  /// "$amount $currencyCode" string so VoiceOver / TalkBack reads
  /// "twelve thousand three hundred forty five point six US dollars"
  /// instead of just the digits.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? TypographyTokens.numericBody).copyWith(
      color: color,
      fontFeatures: TypographyTokens.tabularFigures,
    );
    if (amount != null && AmountPrivacyScope.isHiddenOf(context)) {
      return AmountPrivacyPlaceholder(
        density: compact
            ? AmountPrivacyPlaceholderDensity.compact
            : _placeholderDensity(effectiveStyle),
        style: effectiveStyle,
        textAlign: textAlign,
        semanticsLabel:
            semanticsLabel ??
            AmountPrivacyScope.hiddenSemanticsLabelOf(context),
      );
    }
    final formatted = _format(context);
    return Text(
      formatted,
      style: effectiveStyle,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: semanticsLabel ?? _spokenLabel(formatted),
    );
  }

  String _spokenLabel(String formatted) {
    if (amount == null) return formatted;
    // Pair the formatted number with the ISO currency code so screen
    // readers say e.g. "1,234.56 CNY" instead of bare digits.
    return '$formatted $currencyCode';
  }

  String _format(BuildContext context) {
    if (amount == null) return _emptyForSymbol();
    final loc =
        locale ?? Localizations.maybeLocaleOf(context)?.toString() ?? '';
    final value = amount!;

    final formatter = _cachedFormat(
      locale: loc,
      currencyCode: currencyCode,
      symbolStyle: symbolStyle,
      compact: compact,
      fractionDigits: fractionDigits,
      symbol: symbol,
    );

    final formatted = formatter.format(value.abs());
    if (value < 0) return '-$formatted';
    if (showSign && value > 0) return '+$formatted';
    return formatted;
  }

  String _emptyForSymbol() {
    switch (symbolStyle) {
      case MoneySymbolStyle.symbol:
        return '${symbol ?? _defaultGlyphFor(currencyCode)} —';
      case MoneySymbolStyle.isoCode:
        return '$currencyCode —';
      case MoneySymbolStyle.none:
        return '—';
    }
  }

  String _defaultGlyphFor(String code) => AppFormatters.currencyGlyph(code);

  AmountPrivacyPlaceholderDensity _placeholderDensity(TextStyle style) {
    final fontSize =
        style.fontSize ?? TypographyTokens.numericBody.fontSize ?? 14;
    if (fontSize >= 28) return AmountPrivacyPlaceholderDensity.display;
    if (fontSize >= 18) return AmountPrivacyPlaceholderDensity.title;
    if (fontSize <= 12) return AmountPrivacyPlaceholderDensity.caption;
    return AmountPrivacyPlaceholderDensity.body;
  }
}

/// Signed ledger amount text with shared unit formatting and semantic
/// income/expense colors.
class SignedMoneyText extends StatelessWidget {
  const SignedMoneyText({
    super.key,
    required this.amount,
    required this.unit,
    required this.formatters,
    this.showPositiveSign = true,
    this.colorBySign = true,
    this.style,
    this.color,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.semanticsLabel,
  });

  final Decimal? amount;
  final String unit;
  final AppFormatters formatters;
  final bool showPositiveSign;
  final bool colorBySign;
  final TextStyle? style;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final hidden = amount != null && AmountPrivacyScope.isHiddenOf(context);
    final formatted = amount == null
        ? '—'
        : formatters.signedMoney(
            amount!,
            unit: unit,
            showPositiveSign: showPositiveSign,
          );
    final effectiveColor = color ?? (colorBySign ? _signColor(context) : null);
    final effectiveStyle = (style ?? TypographyTokens.numericBody).copyWith(
      color: effectiveColor,
      fontFeatures: TypographyTokens.tabularFigures,
    );
    if (hidden) {
      return AmountPrivacyPlaceholder(
        style: effectiveStyle.copyWith(color: null),
        textAlign: textAlign,
        density: _placeholderDensity(effectiveStyle),
        semanticsLabel:
            semanticsLabel ??
            AmountPrivacyScope.hiddenSemanticsLabelOf(context),
      );
    }
    return Text(
      formatted,
      style: effectiveStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      semanticsLabel:
          semanticsLabel ??
          (hidden
              ? AmountPrivacyScope.hiddenSemanticsLabelOf(context)
              : '$formatted $unit'),
    );
  }

  Color _signColor(BuildContext context) {
    final value = amount;
    if (value == null || value == Decimal.zero) {
      return context.theme.colors.foreground;
    }
    final semantic = SemanticColors.of(context);
    return value > Decimal.zero ? semantic.success : semantic.danger;
  }

  AmountPrivacyPlaceholderDensity _placeholderDensity(TextStyle style) {
    final fontSize =
        style.fontSize ?? TypographyTokens.numericBody.fontSize ?? 14;
    if (fontSize >= 18) return AmountPrivacyPlaceholderDensity.title;
    if (fontSize <= 12) return AmountPrivacyPlaceholderDensity.caption;
    return AmountPrivacyPlaceholderDensity.body;
  }
}

/// Two-currency money render — primary (typically the report base currency)
/// in the regular weight + size, with a smaller muted caption underneath
/// showing the original-currency amount.
///
/// When [originalAmount] is null, or its currency matches [primaryAmount]'s,
/// the caption is suppressed and the output is visually identical to a plain
/// [MoneyText] — so callers can hand both in unconditionally and let the
/// widget decide whether the second line carries any signal.
class DualMoneyText extends StatelessWidget {
  const DualMoneyText({
    super.key,
    required this.primaryAmount,
    this.originalAmount,
    this.primarySymbolStyle = MoneySymbolStyle.symbol,
    this.captionSymbolStyle = MoneySymbolStyle.isoCode,
    this.primaryStyle,
    this.captionStyle,
    this.color,
    this.captionColor,
    this.locale,
    this.textAlign,
    this.compact = false,
    this.showSign = false,
    this.captionLeading = ' · ',
    this.layout = DualMoneyLayout.inline,
    this.semanticsLabel,
  });

  /// The amount the caller wants to surface first (usually base currency).
  /// `null` renders the standard "no data" placeholder.
  final Money? primaryAmount;

  /// The original-currency value. When `null` or in the same currency as
  /// [primaryAmount], the caption is hidden.
  final Money? originalAmount;

  final MoneySymbolStyle primarySymbolStyle;
  final MoneySymbolStyle captionSymbolStyle;
  final TextStyle? primaryStyle;
  final TextStyle? captionStyle;
  final Color? color;
  final Color? captionColor;
  final String? locale;
  final TextAlign? textAlign;
  final bool compact;
  final bool showSign;

  /// Glyph inserted between primary and caption when [layout] is `inline`.
  final String captionLeading;

  final DualMoneyLayout layout;

  /// Override the spoken accessibility label. Defaults to
  /// `"$primary (original $originalAmount $code)"` when both are present.
  final String? semanticsLabel;

  bool get _captionVisible {
    final orig = originalAmount;
    if (orig == null) return false;
    final base = primaryAmount;
    if (base == null) return false;
    return orig.currency.toUpperCase() != base.currency.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final primary = MoneyText(
      amount: primaryAmount?.amount.toDouble(),
      currencyCode: primaryAmount?.currency ?? 'CNY',
      symbolStyle: primarySymbolStyle,
      style: primaryStyle,
      color: color,
      locale: locale,
      textAlign: textAlign,
      compact: compact,
      showSign: showSign,
      semanticsLabel: semanticsLabel ?? _spokenLabel(),
    );
    if (!_captionVisible) return primary;

    final captionTextStyle = (captionStyle ?? TypographyTokens.numericCaption)
        .copyWith(
          color: captionColor ?? context.theme.colors.mutedForeground,
          fontFeatures: TypographyTokens.tabularFigures,
        );
    final caption = MoneyText(
      amount: originalAmount!.amount.toDouble(),
      currencyCode: originalAmount!.currency,
      symbolStyle: captionSymbolStyle,
      style: captionTextStyle,
      locale: locale,
      compact: compact,
      // Caption never carries a leading `+` even when primary does — the
      // sign on the primary is enough to communicate direction; doubling
      // it just adds visual noise.
      showSign: false,
      // Already covered by primary's semantics label.
      semanticsLabel: '',
    );

    switch (layout) {
      case DualMoneyLayout.inline:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            primary,
            Text(captionLeading, style: captionTextStyle, semanticsLabel: ''),
            caption,
          ],
        );
      case DualMoneyLayout.stacked:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: textAlign == TextAlign.end
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [primary, caption],
        );
    }
  }

  String? _spokenLabel() {
    final base = primaryAmount;
    if (base == null) return null;
    final orig = originalAmount;
    if (orig == null ||
        orig.currency.toUpperCase() == base.currency.toUpperCase()) {
      return '${base.amount} ${base.currency}';
    }
    // Neutral middot-separated form keeps the spoken label localisable
    // without depending on AppLocalizations from a design-system widget.
    // VoiceOver/TalkBack read both amounts + ISO codes verbatim — that
    // is the maximally clear cue and the only thing this label is for.
    return '${base.amount} ${base.currency} · ${orig.amount} ${orig.currency}';
  }
}

/// How [DualMoneyText] arranges primary + caption.
enum DualMoneyLayout {
  /// One line, primary and caption side-by-side separated by [DualMoneyText.captionLeading].
  inline,

  /// Two stacked lines, primary on top.
  stacked,
}
