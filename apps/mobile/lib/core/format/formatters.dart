import 'dart:ui' show Locale;

import 'package:decimal/decimal.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Locale- and currency-aware formatting helpers.
///
/// Decimal-precision values (money, FX rates) are passed as [Decimal] to avoid
/// IEEE-754 drift; everything else accepts [num].
///
/// Construct one [AppFormatters] per active locale, e.g. via a Riverpod
/// provider keyed off `Localizations.localeOf(context)`.
class AppFormatters {
  AppFormatters({required this.locale, this.baseCurrency = 'CNY'})
    : _localeName = locale.toLanguageTag();

  /// Loads `intl` date-symbol data for every supported locale. Call once at
  /// app startup before constructing an [AppFormatters] that will format
  /// dates, otherwise [DateFormat] throws `LocaleDataException`.
  static Future<void> ensureInitialized() async {
    await initializeDateFormatting();
  }

  final Locale locale;
  final String _localeName;

  /// Default ISO-4217 currency used when none is supplied to [currency].
  final String baseCurrency;

  // ---------- Currency ----------

  /// Formats a money amount using the locale's currency conventions.
  ///
  /// [decimalDigits] defaults to the currency's standard fraction digits
  /// (2 for USD/EUR/CNY, 0 for JPY, etc.).
  String currency(
    Decimal amount, {
    String? code,
    int? decimalDigits,
    bool symbol = true,
  }) {
    final currencyCode = code ?? baseCurrency;
    final formatter = symbol
        ? NumberFormat.simpleCurrency(
            locale: _localeName,
            name: currencyCode,
            decimalDigits: decimalDigits,
          )
        : NumberFormat.currency(
            locale: _localeName,
            name: currencyCode,
            symbol: '',
            decimalDigits: decimalDigits,
          );
    return formatter.format(amount.toDouble()).trim();
  }

  /// Compact currency for dashboards: `¥1.2万`, `$1.2K`.
  String compactCurrency(Decimal amount, {String? code}) {
    final currencyCode = code ?? baseCurrency;
    final formatter = NumberFormat.compactSimpleCurrency(
      locale: _localeName,
      name: currencyCode,
    );
    return formatter.format(amount.toDouble());
  }

  // ---------- Numbers ----------

  String number(num value, {int? decimalDigits}) {
    final formatter = NumberFormat.decimalPattern(_localeName);
    if (decimalDigits != null) {
      formatter.minimumFractionDigits = decimalDigits;
      formatter.maximumFractionDigits = decimalDigits;
    }
    return formatter.format(value);
  }

  /// Percentage. [value] is the ratio (0.123 → "12.3%").
  String percent(num value, {int decimalDigits = 2}) {
    final formatter = NumberFormat.decimalPercentPattern(
      locale: _localeName,
      decimalDigits: decimalDigits,
    );
    return formatter.format(value);
  }

  /// Signed percentage with explicit + for positives — useful for P/L deltas.
  String signedPercent(num value, {int decimalDigits = 2}) {
    final base = percent(value.abs(), decimalDigits: decimalDigits);
    if (value > 0) return '+$base';
    if (value < 0) return '-$base';
    return base;
  }

  String compact(num value) {
    return NumberFormat.compact(locale: _localeName).format(value);
  }

  // ---------- Dates ----------

  /// Locale-default short date: zh `2026/04/28`, en `4/28/2026`.
  String date(DateTime value) {
    return DateFormat.yMd(_localeName).format(value);
  }

  /// Long date: zh `2026年4月28日`, en `April 28, 2026`.
  String longDate(DateTime value) {
    return DateFormat.yMMMMd(_localeName).format(value);
  }

  /// Short date + time: zh `2026/04/28 09:30`, en `4/28/2026 9:30 AM`.
  String dateTime(DateTime value) {
    return '${DateFormat.yMd(_localeName).format(value)} '
        '${DateFormat.Hm(_localeName).format(value)}';
  }

  /// Time only.
  String time(DateTime value) {
    return DateFormat.Hm(_localeName).format(value);
  }

  /// Month + year header for transaction lists.
  String monthYear(DateTime value) {
    return DateFormat.yMMM(_localeName).format(value);
  }
}
