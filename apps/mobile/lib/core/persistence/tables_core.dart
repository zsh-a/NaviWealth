part of 'tables.dart';

/// Mixin for sync metadata columns shared by every replicable table.
///
/// Drift table mixins must declare each column the same way a table would
/// (`Column<X> get foo => ...`). Tables that mix this in inherit five
/// extra columns and a [syncIndex] convention that callers compose into
/// their own [Table.indexes] (Drift doesn't currently support index merging
/// across mixins, so each table re-references the indexes they need).
mixin SyncableTable on Table {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  TextColumn get ownerUserId => text()();

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  DateTimeColumn get updatedAt => dateTime()();

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  TextColumn get updatedByDevice => text()();

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  TextColumn get hlc => text().map(const HlcConverter())();

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

@DataClassName('UserRow')
class Users extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SettingsRow')
class SettingsTable extends Table with SyncableTable {
  TextColumn get userId => text()();
  TextColumn get baseCurrency => text().withLength(min: 3, max: 8)();
  TextColumn get themeMode =>
      text().map(const EnumStringConverter(AppThemeMode.values))();
  TextColumn get privacyMode =>
      text().map(const EnumStringConverter(PrivacyMode.values))();
  TextColumn get costBasisMethod =>
      text().map(const EnumStringConverter(CostBasisMethod.values))();

  @override
  String? get tableName => 'settings';

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

@DataClassName('DeviceRow')
class Devices extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get platform =>
      text().map(const EnumStringConverter(DevicePlatform.values))();
  TextColumn get appVersion => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  TextColumn get lastHlc => text().map(const HlcConverter()).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Append-only operation log. Not a SyncableTable: ops *describe* sync
/// events, they aren't themselves synced via the same mechanism — the
/// server consumes them on push and emits them back to peers on pull.
@DataClassName('OpLogRow')
class OpLogs extends Table {
  TextColumn get id => text()();
  TextColumn get ownerUserId => text()();
  TextColumn get deviceId => text()();
  TextColumn get hlc => text().map(const HlcConverter())();
  TextColumn get op => text().map(const EnumStringConverter(OpKind.values))();
  TextColumn get entityTable => text()();
  TextColumn get entityId => text()();
  TextColumn get patchJson => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
