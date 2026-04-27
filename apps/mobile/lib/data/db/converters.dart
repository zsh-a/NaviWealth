import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../domain/hlc.dart';

/// Decimal stored as TEXT — base-10 precision is preserved exactly. We
/// considered storing as INTEGER (smallest unit) per the design spec, but
/// crypto and FX both routinely have variable scale (e.g. 1 BTC =
/// 0.00001234 ETH), so a fixed unit doesn't generalize. TEXT trades a
/// little space for correctness.
class DecimalConverter extends TypeConverter<Decimal, String> {
  const DecimalConverter();

  @override
  Decimal fromSql(String fromDb) => Decimal.parse(fromDb);

  @override
  String toSql(Decimal value) => value.toString();
}

/// HLC stored as its packed wire form (`<wall>:<counter>-<node>`). Doing it
/// this way means SQL `ORDER BY hlc` gives the wrong order — *do not* sort
/// on this column directly; sort on `wall_millis` + `counter` if you need
/// causal order in SQL, or load and sort in Dart.
class HlcConverter extends TypeConverter<Hlc, String> {
  const HlcConverter();

  @override
  Hlc fromSql(String fromDb) => Hlc.parse(fromDb);

  @override
  String toSql(Hlc value) => value.toString();
}

/// Generic enum ↔ name converter. Adding a new value at the end is a
/// backwards-compatible change; renaming or reordering needs a migration.
class EnumStringConverter<T extends Enum> extends TypeConverter<T, String> {
  const EnumStringConverter(this.values);

  final List<T> values;

  @override
  T fromSql(String fromDb) => values.byName(fromDb);

  @override
  String toSql(T value) => value.name;
}
