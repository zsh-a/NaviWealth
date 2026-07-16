import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

const Set<String> _knownFiatCodes = {
  'AED',
  'AUD',
  'BRL',
  'CAD',
  'CHF',
  'CNY',
  'EUR',
  'GBP',
  'HKD',
  'INR',
  'JPY',
  'KRW',
  'MXN',
  'NZD',
  'RUB',
  'SGD',
  'TWD',
  'USD',
  'ZAR',
};

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
  ///
  /// Uses a deterministic inline algorithm so CJK unit suffixes never render
  /// as a separate vertical glyph (ICU compact currency can look broken with
  /// Inter/Outfit tabular figures).
  String compactCurrency(Decimal amount, {String? code}) {
    final currencyCode = code ?? baseCurrency;
    final value = amount.toDouble();
    if (!value.isFinite) {
      return currency(amount, code: currencyCode);
    }
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    final glyph = currencyGlyph(currencyCode);
    final zh = locale.languageCode.toLowerCase() == 'zh';

    if (zh) {
      if (abs >= 1e8) {
        return '$sign$glyph${_compactNumber(abs / 1e8)}亿';
      }
      if (abs >= 1e4) {
        return '$sign$glyph${_compactNumber(abs / 1e4)}万';
      }
      return currency(amount, code: currencyCode);
    }

    if (abs >= 1e9) {
      return '$sign$glyph${_compactNumber(abs / 1e9)}B';
    }
    if (abs >= 1e6) {
      return '$sign$glyph${_compactNumber(abs / 1e6)}M';
    }
    if (abs >= 1e3) {
      return '$sign$glyph${_compactNumber(abs / 1e3)}K';
    }
    return currency(amount, code: currencyCode);
  }

  /// Compact body used by [compactCurrency] — trims trailing zeros.
  static String _compactNumber(double n) {
    if (n >= 100) return n.toStringAsFixed(0);
    if (n >= 10) {
      final one = n.toStringAsFixed(1);
      return one.endsWith('.0') ? one.substring(0, one.length - 2) : one;
    }
    final two = n.toStringAsFixed(2);
    if (two.endsWith('00')) return two.substring(0, two.length - 3);
    if (two.endsWith('0')) return two.substring(0, two.length - 1);
    return two;
  }

  /// Formats a ledger amount with a stable sign, grouping, and unit display.
  ///
  /// Fiat units use the currency's standard maximum fraction digits and trim
  /// trailing zeros (`+$1,234.5`). Commodities and securities preserve their
  /// meaningful quantity precision and append the asset code (`-0.25 BTC`,
  /// `+10 AAPL`). Security ids of the form `market:symbol` display only the
  /// symbol.
  String signedMoney(
    Decimal amount, {
    required String unit,
    bool showPositiveSign = true,
  }) {
    final formatted = _formatUnitAmount(amount.abs(), unit: unit);
    if (amount < Decimal.zero) return '-$formatted';
    if (showPositiveSign && amount > Decimal.zero) return '+$formatted';
    return formatted;
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

  String _formatUnitAmount(Decimal amount, {required String unit}) {
    if (_isKnownFiatCode(unit)) {
      final formatter = NumberFormat.simpleCurrency(
        locale: _localeName,
        name: unit.toUpperCase(),
      )..minimumFractionDigits = 0;
      return formatter.format(amount.toDouble());
    }

    final scale = _trimmedFractionDigits(amount);
    final formatter = NumberFormat.decimalPattern(_localeName)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = scale;
    return '${formatter.format(amount.toDouble())} ${assetCode(unit)}';
  }

  /// Display code for commodity/security units. `us_stock:AAPL` becomes
  /// `AAPL`; plain units such as `BTC` pass through unchanged.
  static String assetCode(String unit) {
    final colon = unit.indexOf(':');
    return colon < 0 ? unit : unit.substring(colon + 1);
  }

  int _trimmedFractionDigits(Decimal amount) {
    final text = amount.toString();
    final dot = text.indexOf('.');
    if (dot < 0) return 0;
    final fraction = text.substring(dot + 1).replaceFirst(RegExp(r'0+$'), '');
    return fraction.length.clamp(0, 12).toInt();
  }

  bool _isKnownFiatCode(String unit) =>
      _knownFiatCodes.contains(unit.toUpperCase());

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

  /// Month + day without year: zh `4月28日`, en `Apr 28`.
  String monthDay(DateTime value) {
    return DateFormat.MMMd(_localeName).format(value);
  }

  // ---------- Relative time ----------

  /// Human-readable relative time string ("3 minutes ago", "昨天", etc.).
  ///
  /// [justNow], [minutesAgo], [hoursAgo], [daysAgo] are localized templates
  /// with a single `{n}` placeholder (e.g. l10n.aiChatRelativeMinutesAgo).
  /// [dateFallback] formats dates older than [maxDays] days.
  /// [maxDays] controls when the fallback date is used (default 7).
  static String relativeTime(
    DateTime when, {
    required String justNow,
    required String Function(int) minutesAgo,
    required String Function(int) hoursAgo,
    required String Function(int) daysAgo,
    required String Function(DateTime) dateFallback,
    int maxDays = 7,
  }) {
    final diff = DateTime.now().difference(when.toLocal());
    if (diff.inMinutes < 1) return justNow;
    if (diff.inMinutes < 60) return minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return hoursAgo(diff.inHours);
    if (diff.inDays < maxDays) return daysAgo(diff.inDays);
    return dateFallback(when.toLocal());
  }

  // ---------- Static helpers ----------

  /// Currency code → display glyph. Falls back to [code] itself for unknowns.
  static String currencyGlyph(String code) {
    switch (code.toUpperCase()) {
      case 'CNY':
      case 'JPY':
        return '¥';
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'HKD':
        return r'HK$';
      default:
        return code;
    }
  }

  /// Converts a [DateTime] to a UTC `YYYY-MM-DD` string key.
  static String utcDayKey(DateTime t) =>
      t.toUtc().toIso8601String().substring(0, 10);
}

/// Lightweight static formatting helpers that use the system default locale.
/// Use [AppFormatters] when a specific locale is required.
class Fmt {
  Fmt._();

  /// Locale-default number formatting.
  static String number(num value, {int? decimalDigits}) {
    final formatter = NumberFormat.decimalPattern();
    if (decimalDigits != null) {
      formatter.minimumFractionDigits = decimalDigits;
      formatter.maximumFractionDigits = decimalDigits;
    }
    return formatter.format(value);
  }

  /// Signed percentage with explicit + for positives.
  /// [value] is the ratio (0.123 → "+12.3%").
  static String signedPercent(num value, {int decimalDigits = 2}) {
    final formatter = NumberFormat.decimalPercentPattern(
      decimalDigits: decimalDigits,
    );
    final base = formatter.format(value.abs());
    if (value > 0) return '+$base';
    if (value < 0) return '-$base';
    return base;
  }
}

/// Extension on [Decimal] for safe double→Decimal conversion.
extension DecimalX on Decimal {
  /// Creates a [Decimal] from a [double] with the given number of fraction
  /// [scale] digits, avoiding IEEE-754 drift.
  static Decimal fromDouble(double v, {int scale = 2}) =>
      Decimal.parse(v.toStringAsFixed(scale));
}

/// Parses a user-input string into [Decimal], returning `null` for empty,
/// whitespace-only, or unparseable input. Trims whitespace automatically.
Decimal? parseDecimal(String? input) {
  if (input == null) return null;
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  return Decimal.tryParse(trimmed);
}

/// Reads a [TextEditingController]'s text and parses it to [Decimal].
/// Returns `null` for empty or unparseable input.
Decimal? parseDecimalController(TextEditingController controller) =>
    parseDecimal(controller.text);
