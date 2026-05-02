// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $UsersTable extends Users with TableInfo<$UsersTable, UserRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($UsersTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    email,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $UsersTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
}

class UserRow extends DataClass implements Insertable<UserRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String name;
  final String? email;
  final DateTime createdAt;
  const UserRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.name,
    this.email,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($UsersTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      name: Value(name),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      createdAt: Value(createdAt),
    );
  }

  factory UserRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      email: serializer.fromJson<String?>(json['email']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'email': serializer.toJson<String?>(email),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  UserRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? name,
    Value<String?> email = const Value.absent(),
    DateTime? createdAt,
  }) => UserRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    name: name ?? this.name,
    email: email.present ? email.value : this.email,
    createdAt: createdAt ?? this.createdAt,
  );
  UserRow copyWithCompanion(UsersCompanion data) {
    return UserRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      email: data.email.present ? data.email.value : this.email,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('email: $email, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    email,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.name == this.name &&
          other.email == this.email &&
          other.createdAt == this.createdAt);
}

class UsersCompanion extends UpdateCompanion<UserRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> email;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const UsersCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.email = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String name,
    this.email = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<UserRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? email,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? email,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>($UsersTable.$converterhlc.toSql(hlc.value));
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('email: $email, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTableTable extends SettingsTable
    with TableInfo<$SettingsTableTable, SettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($SettingsTableTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseCurrencyMeta = const VerificationMeta(
    'baseCurrency',
  );
  @override
  late final GeneratedColumn<String> baseCurrency = GeneratedColumn<String>(
    'base_currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AppThemeMode, String> themeMode =
      GeneratedColumn<String>(
        'theme_mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AppThemeMode>($SettingsTableTable.$converterthemeMode);
  @override
  late final GeneratedColumnWithTypeConverter<PrivacyMode, String> privacyMode =
      GeneratedColumn<String>(
        'privacy_mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PrivacyMode>($SettingsTableTable.$converterprivacyMode);
  @override
  late final GeneratedColumnWithTypeConverter<CostBasisMethod, String>
  costBasisMethod =
      GeneratedColumn<String>(
        'cost_basis_method',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CostBasisMethod>(
        $SettingsTableTable.$convertercostBasisMethod,
      );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    userId,
    baseCurrency,
    themeMode,
    privacyMode,
    costBasisMethod,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('base_currency')) {
      context.handle(
        _baseCurrencyMeta,
        baseCurrency.isAcceptableOrUnknown(
          data['base_currency']!,
          _baseCurrencyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseCurrencyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  SettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingsRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $SettingsTableTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      baseCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_currency'],
      )!,
      themeMode: $SettingsTableTable.$converterthemeMode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}theme_mode'],
        )!,
      ),
      privacyMode: $SettingsTableTable.$converterprivacyMode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}privacy_mode'],
        )!,
      ),
      costBasisMethod: $SettingsTableTable.$convertercostBasisMethod.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}cost_basis_method'],
        )!,
      ),
    );
  }

  @override
  $SettingsTableTable createAlias(String alias) {
    return $SettingsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<AppThemeMode, String> $converterthemeMode =
      const EnumStringConverter(AppThemeMode.values);
  static TypeConverter<PrivacyMode, String> $converterprivacyMode =
      const EnumStringConverter(PrivacyMode.values);
  static TypeConverter<CostBasisMethod, String> $convertercostBasisMethod =
      const EnumStringConverter(CostBasisMethod.values);
}

class SettingsRow extends DataClass implements Insertable<SettingsRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String userId;
  final String baseCurrency;
  final AppThemeMode themeMode;
  final PrivacyMode privacyMode;
  final CostBasisMethod costBasisMethod;
  const SettingsRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.userId,
    required this.baseCurrency,
    required this.themeMode,
    required this.privacyMode,
    required this.costBasisMethod,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>(
        $SettingsTableTable.$converterhlc.toSql(hlc),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['user_id'] = Variable<String>(userId);
    map['base_currency'] = Variable<String>(baseCurrency);
    {
      map['theme_mode'] = Variable<String>(
        $SettingsTableTable.$converterthemeMode.toSql(themeMode),
      );
    }
    {
      map['privacy_mode'] = Variable<String>(
        $SettingsTableTable.$converterprivacyMode.toSql(privacyMode),
      );
    }
    {
      map['cost_basis_method'] = Variable<String>(
        $SettingsTableTable.$convertercostBasisMethod.toSql(costBasisMethod),
      );
    }
    return map;
  }

  SettingsTableCompanion toCompanion(bool nullToAbsent) {
    return SettingsTableCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      userId: Value(userId),
      baseCurrency: Value(baseCurrency),
      themeMode: Value(themeMode),
      privacyMode: Value(privacyMode),
      costBasisMethod: Value(costBasisMethod),
    );
  }

  factory SettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingsRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      userId: serializer.fromJson<String>(json['userId']),
      baseCurrency: serializer.fromJson<String>(json['baseCurrency']),
      themeMode: serializer.fromJson<AppThemeMode>(json['themeMode']),
      privacyMode: serializer.fromJson<PrivacyMode>(json['privacyMode']),
      costBasisMethod: serializer.fromJson<CostBasisMethod>(
        json['costBasisMethod'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'userId': serializer.toJson<String>(userId),
      'baseCurrency': serializer.toJson<String>(baseCurrency),
      'themeMode': serializer.toJson<AppThemeMode>(themeMode),
      'privacyMode': serializer.toJson<PrivacyMode>(privacyMode),
      'costBasisMethod': serializer.toJson<CostBasisMethod>(costBasisMethod),
    };
  }

  SettingsRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? userId,
    String? baseCurrency,
    AppThemeMode? themeMode,
    PrivacyMode? privacyMode,
    CostBasisMethod? costBasisMethod,
  }) => SettingsRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    userId: userId ?? this.userId,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    themeMode: themeMode ?? this.themeMode,
    privacyMode: privacyMode ?? this.privacyMode,
    costBasisMethod: costBasisMethod ?? this.costBasisMethod,
  );
  SettingsRow copyWithCompanion(SettingsTableCompanion data) {
    return SettingsRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      userId: data.userId.present ? data.userId.value : this.userId,
      baseCurrency: data.baseCurrency.present
          ? data.baseCurrency.value
          : this.baseCurrency,
      themeMode: data.themeMode.present ? data.themeMode.value : this.themeMode,
      privacyMode: data.privacyMode.present
          ? data.privacyMode.value
          : this.privacyMode,
      costBasisMethod: data.costBasisMethod.present
          ? data.costBasisMethod.value
          : this.costBasisMethod,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('userId: $userId, ')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('themeMode: $themeMode, ')
          ..write('privacyMode: $privacyMode, ')
          ..write('costBasisMethod: $costBasisMethod')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    userId,
    baseCurrency,
    themeMode,
    privacyMode,
    costBasisMethod,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.userId == this.userId &&
          other.baseCurrency == this.baseCurrency &&
          other.themeMode == this.themeMode &&
          other.privacyMode == this.privacyMode &&
          other.costBasisMethod == this.costBasisMethod);
}

class SettingsTableCompanion extends UpdateCompanion<SettingsRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> userId;
  final Value<String> baseCurrency;
  final Value<AppThemeMode> themeMode;
  final Value<PrivacyMode> privacyMode;
  final Value<CostBasisMethod> costBasisMethod;
  final Value<int> rowid;
  const SettingsTableCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.baseCurrency = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.privacyMode = const Value.absent(),
    this.costBasisMethod = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsTableCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String userId,
    required String baseCurrency,
    required AppThemeMode themeMode,
    required PrivacyMode privacyMode,
    required CostBasisMethod costBasisMethod,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       userId = Value(userId),
       baseCurrency = Value(baseCurrency),
       themeMode = Value(themeMode),
       privacyMode = Value(privacyMode),
       costBasisMethod = Value(costBasisMethod);
  static Insertable<SettingsRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? userId,
    Expression<String>? baseCurrency,
    Expression<String>? themeMode,
    Expression<String>? privacyMode,
    Expression<String>? costBasisMethod,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (userId != null) 'user_id': userId,
      if (baseCurrency != null) 'base_currency': baseCurrency,
      if (themeMode != null) 'theme_mode': themeMode,
      if (privacyMode != null) 'privacy_mode': privacyMode,
      if (costBasisMethod != null) 'cost_basis_method': costBasisMethod,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsTableCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? userId,
    Value<String>? baseCurrency,
    Value<AppThemeMode>? themeMode,
    Value<PrivacyMode>? privacyMode,
    Value<CostBasisMethod>? costBasisMethod,
    Value<int>? rowid,
  }) {
    return SettingsTableCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      userId: userId ?? this.userId,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      themeMode: themeMode ?? this.themeMode,
      privacyMode: privacyMode ?? this.privacyMode,
      costBasisMethod: costBasisMethod ?? this.costBasisMethod,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $SettingsTableTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (baseCurrency.present) {
      map['base_currency'] = Variable<String>(baseCurrency.value);
    }
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(
        $SettingsTableTable.$converterthemeMode.toSql(themeMode.value),
      );
    }
    if (privacyMode.present) {
      map['privacy_mode'] = Variable<String>(
        $SettingsTableTable.$converterprivacyMode.toSql(privacyMode.value),
      );
    }
    if (costBasisMethod.present) {
      map['cost_basis_method'] = Variable<String>(
        $SettingsTableTable.$convertercostBasisMethod.toSql(
          costBasisMethod.value,
        ),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsTableCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('userId: $userId, ')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('themeMode: $themeMode, ')
          ..write('privacyMode: $privacyMode, ')
          ..write('costBasisMethod: $costBasisMethod, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountsTable extends Accounts
    with TableInfo<$AccountsTable, AccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($AccountsTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AccountType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AccountType>($AccountsTable.$convertertype);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _institutionMeta = const VerificationMeta(
    'institution',
  );
  @override
  late final GeneratedColumn<String> institution = GeneratedColumn<String>(
    'institution',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accountNumberMeta = const VerificationMeta(
    'accountNumber',
  );
  @override
  late final GeneratedColumn<String> accountNumber = GeneratedColumn<String>(
    'account_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<AccountCategory, String>
  category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: Constant(AccountCategory.asset.name),
  ).withConverter<AccountCategory>($AccountsTable.$convertercategory);
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    type,
    name,
    currency,
    institution,
    accountNumber,
    note,
    archived,
    category,
    parentId,
    icon,
    color,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('institution')) {
      context.handle(
        _institutionMeta,
        institution.isAcceptableOrUnknown(
          data['institution']!,
          _institutionMeta,
        ),
      );
    }
    if (data.containsKey('account_number')) {
      context.handle(
        _accountNumberMeta,
        accountNumber.isAcceptableOrUnknown(
          data['account_number']!,
          _accountNumberMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $AccountsTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: $AccountsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      institution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}institution'],
      ),
      accountNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_number'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      category: $AccountsTable.$convertercategory.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}category'],
        )!,
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<AccountType, String> $convertertype =
      const EnumStringConverter(AccountType.values);
  static TypeConverter<AccountCategory, String> $convertercategory =
      const EnumStringConverter(AccountCategory.values);
}

class AccountRow extends DataClass implements Insertable<AccountRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final AccountType type;
  final String name;
  final String currency;
  final String? institution;
  final String? accountNumber;
  final String? note;
  final bool archived;

  /// FIR-126 — accounting classification (asset / liability / income /
  /// expense / equity). See [AccountCategory] for the why and the
  /// migration in `app_database.dart` (v8) for the back-fill rules.
  ///
  /// Defaulting to `asset` at the column level lets us add the column
  /// non-null in the v8 ALTER TABLE without a separate UPDATE step on
  /// users who only ever held positive balances; the migration still
  /// rewrites the seven non-`liability` AccountTypes explicitly so the
  /// fact stays expressed in code rather than relying on the SQL default.
  final AccountCategory category;

  /// FIR-130 — id of this account's parent in the Beancount-style tree.
  /// NULL on top-level rows; otherwise points at another row in this
  /// table. No FK at the SQL layer because sync-borne reorders need to
  /// land before the parent has caught up.
  final String? parentId;

  /// FIR-130 — Material icon name for the account avatar (replaces
  /// `expense_categories.icon`).
  final String? icon;

  /// FIR-130 — color token (hex string or design-token id) for the
  /// account avatar (replaces `expense_categories.color`).
  final String? color;
  const AccountRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.type,
    required this.name,
    required this.currency,
    this.institution,
    this.accountNumber,
    this.note,
    required this.archived,
    required this.category,
    this.parentId,
    this.icon,
    this.color,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($AccountsTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    {
      map['type'] = Variable<String>($AccountsTable.$convertertype.toSql(type));
    }
    map['name'] = Variable<String>(name);
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || institution != null) {
      map['institution'] = Variable<String>(institution);
    }
    if (!nullToAbsent || accountNumber != null) {
      map['account_number'] = Variable<String>(accountNumber);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['archived'] = Variable<bool>(archived);
    {
      map['category'] = Variable<String>(
        $AccountsTable.$convertercategory.toSql(category),
      );
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      type: Value(type),
      name: Value(name),
      currency: Value(currency),
      institution: institution == null && nullToAbsent
          ? const Value.absent()
          : Value(institution),
      accountNumber: accountNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(accountNumber),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      archived: Value(archived),
      category: Value(category),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
    );
  }

  factory AccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<AccountType>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      currency: serializer.fromJson<String>(json['currency']),
      institution: serializer.fromJson<String?>(json['institution']),
      accountNumber: serializer.fromJson<String?>(json['accountNumber']),
      note: serializer.fromJson<String?>(json['note']),
      archived: serializer.fromJson<bool>(json['archived']),
      category: serializer.fromJson<AccountCategory>(json['category']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      icon: serializer.fromJson<String?>(json['icon']),
      color: serializer.fromJson<String?>(json['color']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<AccountType>(type),
      'name': serializer.toJson<String>(name),
      'currency': serializer.toJson<String>(currency),
      'institution': serializer.toJson<String?>(institution),
      'accountNumber': serializer.toJson<String?>(accountNumber),
      'note': serializer.toJson<String?>(note),
      'archived': serializer.toJson<bool>(archived),
      'category': serializer.toJson<AccountCategory>(category),
      'parentId': serializer.toJson<String?>(parentId),
      'icon': serializer.toJson<String?>(icon),
      'color': serializer.toJson<String?>(color),
    };
  }

  AccountRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    AccountType? type,
    String? name,
    String? currency,
    Value<String?> institution = const Value.absent(),
    Value<String?> accountNumber = const Value.absent(),
    Value<String?> note = const Value.absent(),
    bool? archived,
    AccountCategory? category,
    Value<String?> parentId = const Value.absent(),
    Value<String?> icon = const Value.absent(),
    Value<String?> color = const Value.absent(),
  }) => AccountRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    type: type ?? this.type,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    institution: institution.present ? institution.value : this.institution,
    accountNumber: accountNumber.present
        ? accountNumber.value
        : this.accountNumber,
    note: note.present ? note.value : this.note,
    archived: archived ?? this.archived,
    category: category ?? this.category,
    parentId: parentId.present ? parentId.value : this.parentId,
    icon: icon.present ? icon.value : this.icon,
    color: color.present ? color.value : this.color,
  );
  AccountRow copyWithCompanion(AccountsCompanion data) {
    return AccountRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      currency: data.currency.present ? data.currency.value : this.currency,
      institution: data.institution.present
          ? data.institution.value
          : this.institution,
      accountNumber: data.accountNumber.present
          ? data.accountNumber.value
          : this.accountNumber,
      note: data.note.present ? data.note.value : this.note,
      archived: data.archived.present ? data.archived.value : this.archived,
      category: data.category.present ? data.category.value : this.category,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('institution: $institution, ')
          ..write('accountNumber: $accountNumber, ')
          ..write('note: $note, ')
          ..write('archived: $archived, ')
          ..write('category: $category, ')
          ..write('parentId: $parentId, ')
          ..write('icon: $icon, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    type,
    name,
    currency,
    institution,
    accountNumber,
    note,
    archived,
    category,
    parentId,
    icon,
    color,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.type == this.type &&
          other.name == this.name &&
          other.currency == this.currency &&
          other.institution == this.institution &&
          other.accountNumber == this.accountNumber &&
          other.note == this.note &&
          other.archived == this.archived &&
          other.category == this.category &&
          other.parentId == this.parentId &&
          other.icon == this.icon &&
          other.color == this.color);
}

class AccountsCompanion extends UpdateCompanion<AccountRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<AccountType> type;
  final Value<String> name;
  final Value<String> currency;
  final Value<String?> institution;
  final Value<String?> accountNumber;
  final Value<String?> note;
  final Value<bool> archived;
  final Value<AccountCategory> category;
  final Value<String?> parentId;
  final Value<String?> icon;
  final Value<String?> color;
  final Value<int> rowid;
  const AccountsCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.currency = const Value.absent(),
    this.institution = const Value.absent(),
    this.accountNumber = const Value.absent(),
    this.note = const Value.absent(),
    this.archived = const Value.absent(),
    this.category = const Value.absent(),
    this.parentId = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required AccountType type,
    required String name,
    required String currency,
    this.institution = const Value.absent(),
    this.accountNumber = const Value.absent(),
    this.note = const Value.absent(),
    this.archived = const Value.absent(),
    this.category = const Value.absent(),
    this.parentId = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       type = Value(type),
       name = Value(name),
       currency = Value(currency);
  static Insertable<AccountRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? currency,
    Expression<String>? institution,
    Expression<String>? accountNumber,
    Expression<String>? note,
    Expression<bool>? archived,
    Expression<String>? category,
    Expression<String>? parentId,
    Expression<String>? icon,
    Expression<String>? color,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (currency != null) 'currency': currency,
      if (institution != null) 'institution': institution,
      if (accountNumber != null) 'account_number': accountNumber,
      if (note != null) 'note': note,
      if (archived != null) 'archived': archived,
      if (category != null) 'category': category,
      if (parentId != null) 'parent_id': parentId,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<AccountType>? type,
    Value<String>? name,
    Value<String>? currency,
    Value<String?>? institution,
    Value<String?>? accountNumber,
    Value<String?>? note,
    Value<bool>? archived,
    Value<AccountCategory>? category,
    Value<String?>? parentId,
    Value<String?>? icon,
    Value<String?>? color,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      institution: institution ?? this.institution,
      accountNumber: accountNumber ?? this.accountNumber,
      note: note ?? this.note,
      archived: archived ?? this.archived,
      category: category ?? this.category,
      parentId: parentId ?? this.parentId,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $AccountsTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $AccountsTable.$convertertype.toSql(type.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (institution.present) {
      map['institution'] = Variable<String>(institution.value);
    }
    if (accountNumber.present) {
      map['account_number'] = Variable<String>(accountNumber.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(
        $AccountsTable.$convertercategory.toSql(category.value),
      );
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('institution: $institution, ')
          ..write('accountNumber: $accountNumber, ')
          ..write('note: $note, ')
          ..write('archived: $archived, ')
          ..write('category: $category, ')
          ..write('parentId: $parentId, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssetsTable extends Assets with TableInfo<$AssetsTable, AssetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($AssetsTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AssetType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AssetType>($AssetsTable.$convertertype);
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _marketMeta = const VerificationMeta('market');
  @override
  late final GeneratedColumn<String> market = GeneratedColumn<String>(
    'market',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _industryMeta = const VerificationMeta(
    'industry',
  );
  @override
  late final GeneratedColumn<String> industry = GeneratedColumn<String>(
    'industry',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  @override
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
    'region',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isinMeta = const VerificationMeta('isin');
  @override
  late final GeneratedColumn<String> isin = GeneratedColumn<String>(
    'isin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal?, String> lastPrice =
      GeneratedColumn<String>(
        'last_price',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Decimal?>($AssetsTable.$converterlastPricen);
  static const VerificationMeta _lastPriceAtMeta = const VerificationMeta(
    'lastPriceAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPriceAt = GeneratedColumn<DateTime>(
    'last_price_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logoUrlMeta = const VerificationMeta(
    'logoUrl',
  );
  @override
  late final GeneratedColumn<String> logoUrl = GeneratedColumn<String>(
    'logo_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    type,
    symbol,
    currency,
    name,
    market,
    industry,
    region,
    isin,
    lastPrice,
    lastPriceAt,
    logoUrl,
    metadataJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('market')) {
      context.handle(
        _marketMeta,
        market.isAcceptableOrUnknown(data['market']!, _marketMeta),
      );
    }
    if (data.containsKey('industry')) {
      context.handle(
        _industryMeta,
        industry.isAcceptableOrUnknown(data['industry']!, _industryMeta),
      );
    }
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    }
    if (data.containsKey('isin')) {
      context.handle(
        _isinMeta,
        isin.isAcceptableOrUnknown(data['isin']!, _isinMeta),
      );
    }
    if (data.containsKey('last_price_at')) {
      context.handle(
        _lastPriceAtMeta,
        lastPriceAt.isAcceptableOrUnknown(
          data['last_price_at']!,
          _lastPriceAtMeta,
        ),
      );
    }
    if (data.containsKey('logo_url')) {
      context.handle(
        _logoUrlMeta,
        logoUrl.isAcceptableOrUnknown(data['logo_url']!, _logoUrlMeta),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $AssetsTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: $AssetsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      market: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}market'],
      ),
      industry: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}industry'],
      ),
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      ),
      isin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}isin'],
      ),
      lastPrice: $AssetsTable.$converterlastPricen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_price'],
        ),
      ),
      lastPriceAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_price_at'],
      ),
      logoUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logo_url'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
    );
  }

  @override
  $AssetsTable createAlias(String alias) {
    return $AssetsTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<AssetType, String> $convertertype =
      const EnumStringConverter(AssetType.values);
  static TypeConverter<Decimal, String> $converterlastPrice =
      const DecimalConverter();
  static TypeConverter<Decimal?, String?> $converterlastPricen =
      NullAwareTypeConverter.wrap($converterlastPrice);
}

class AssetRow extends DataClass implements Insertable<AssetRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final AssetType type;
  final String symbol;
  final String currency;
  final String? name;
  final String? market;
  final String? industry;
  final String? region;
  final String? isin;
  final Decimal? lastPrice;
  final DateTime? lastPriceAt;
  final String? logoUrl;
  final String? metadataJson;
  const AssetRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.type,
    required this.symbol,
    required this.currency,
    this.name,
    this.market,
    this.industry,
    this.region,
    this.isin,
    this.lastPrice,
    this.lastPriceAt,
    this.logoUrl,
    this.metadataJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($AssetsTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    {
      map['type'] = Variable<String>($AssetsTable.$convertertype.toSql(type));
    }
    map['symbol'] = Variable<String>(symbol);
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || market != null) {
      map['market'] = Variable<String>(market);
    }
    if (!nullToAbsent || industry != null) {
      map['industry'] = Variable<String>(industry);
    }
    if (!nullToAbsent || region != null) {
      map['region'] = Variable<String>(region);
    }
    if (!nullToAbsent || isin != null) {
      map['isin'] = Variable<String>(isin);
    }
    if (!nullToAbsent || lastPrice != null) {
      map['last_price'] = Variable<String>(
        $AssetsTable.$converterlastPricen.toSql(lastPrice),
      );
    }
    if (!nullToAbsent || lastPriceAt != null) {
      map['last_price_at'] = Variable<DateTime>(lastPriceAt);
    }
    if (!nullToAbsent || logoUrl != null) {
      map['logo_url'] = Variable<String>(logoUrl);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    return map;
  }

  AssetsCompanion toCompanion(bool nullToAbsent) {
    return AssetsCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      type: Value(type),
      symbol: Value(symbol),
      currency: Value(currency),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      market: market == null && nullToAbsent
          ? const Value.absent()
          : Value(market),
      industry: industry == null && nullToAbsent
          ? const Value.absent()
          : Value(industry),
      region: region == null && nullToAbsent
          ? const Value.absent()
          : Value(region),
      isin: isin == null && nullToAbsent ? const Value.absent() : Value(isin),
      lastPrice: lastPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPrice),
      lastPriceAt: lastPriceAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPriceAt),
      logoUrl: logoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(logoUrl),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
    );
  }

  factory AssetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<AssetType>(json['type']),
      symbol: serializer.fromJson<String>(json['symbol']),
      currency: serializer.fromJson<String>(json['currency']),
      name: serializer.fromJson<String?>(json['name']),
      market: serializer.fromJson<String?>(json['market']),
      industry: serializer.fromJson<String?>(json['industry']),
      region: serializer.fromJson<String?>(json['region']),
      isin: serializer.fromJson<String?>(json['isin']),
      lastPrice: serializer.fromJson<Decimal?>(json['lastPrice']),
      lastPriceAt: serializer.fromJson<DateTime?>(json['lastPriceAt']),
      logoUrl: serializer.fromJson<String?>(json['logoUrl']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<AssetType>(type),
      'symbol': serializer.toJson<String>(symbol),
      'currency': serializer.toJson<String>(currency),
      'name': serializer.toJson<String?>(name),
      'market': serializer.toJson<String?>(market),
      'industry': serializer.toJson<String?>(industry),
      'region': serializer.toJson<String?>(region),
      'isin': serializer.toJson<String?>(isin),
      'lastPrice': serializer.toJson<Decimal?>(lastPrice),
      'lastPriceAt': serializer.toJson<DateTime?>(lastPriceAt),
      'logoUrl': serializer.toJson<String?>(logoUrl),
      'metadataJson': serializer.toJson<String?>(metadataJson),
    };
  }

  AssetRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    AssetType? type,
    String? symbol,
    String? currency,
    Value<String?> name = const Value.absent(),
    Value<String?> market = const Value.absent(),
    Value<String?> industry = const Value.absent(),
    Value<String?> region = const Value.absent(),
    Value<String?> isin = const Value.absent(),
    Value<Decimal?> lastPrice = const Value.absent(),
    Value<DateTime?> lastPriceAt = const Value.absent(),
    Value<String?> logoUrl = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
  }) => AssetRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    type: type ?? this.type,
    symbol: symbol ?? this.symbol,
    currency: currency ?? this.currency,
    name: name.present ? name.value : this.name,
    market: market.present ? market.value : this.market,
    industry: industry.present ? industry.value : this.industry,
    region: region.present ? region.value : this.region,
    isin: isin.present ? isin.value : this.isin,
    lastPrice: lastPrice.present ? lastPrice.value : this.lastPrice,
    lastPriceAt: lastPriceAt.present ? lastPriceAt.value : this.lastPriceAt,
    logoUrl: logoUrl.present ? logoUrl.value : this.logoUrl,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
  );
  AssetRow copyWithCompanion(AssetsCompanion data) {
    return AssetRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      currency: data.currency.present ? data.currency.value : this.currency,
      name: data.name.present ? data.name.value : this.name,
      market: data.market.present ? data.market.value : this.market,
      industry: data.industry.present ? data.industry.value : this.industry,
      region: data.region.present ? data.region.value : this.region,
      isin: data.isin.present ? data.isin.value : this.isin,
      lastPrice: data.lastPrice.present ? data.lastPrice.value : this.lastPrice,
      lastPriceAt: data.lastPriceAt.present
          ? data.lastPriceAt.value
          : this.lastPriceAt,
      logoUrl: data.logoUrl.present ? data.logoUrl.value : this.logoUrl,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('symbol: $symbol, ')
          ..write('currency: $currency, ')
          ..write('name: $name, ')
          ..write('market: $market, ')
          ..write('industry: $industry, ')
          ..write('region: $region, ')
          ..write('isin: $isin, ')
          ..write('lastPrice: $lastPrice, ')
          ..write('lastPriceAt: $lastPriceAt, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('metadataJson: $metadataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    type,
    symbol,
    currency,
    name,
    market,
    industry,
    region,
    isin,
    lastPrice,
    lastPriceAt,
    logoUrl,
    metadataJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.type == this.type &&
          other.symbol == this.symbol &&
          other.currency == this.currency &&
          other.name == this.name &&
          other.market == this.market &&
          other.industry == this.industry &&
          other.region == this.region &&
          other.isin == this.isin &&
          other.lastPrice == this.lastPrice &&
          other.lastPriceAt == this.lastPriceAt &&
          other.logoUrl == this.logoUrl &&
          other.metadataJson == this.metadataJson);
}

class AssetsCompanion extends UpdateCompanion<AssetRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<AssetType> type;
  final Value<String> symbol;
  final Value<String> currency;
  final Value<String?> name;
  final Value<String?> market;
  final Value<String?> industry;
  final Value<String?> region;
  final Value<String?> isin;
  final Value<Decimal?> lastPrice;
  final Value<DateTime?> lastPriceAt;
  final Value<String?> logoUrl;
  final Value<String?> metadataJson;
  final Value<int> rowid;
  const AssetsCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.symbol = const Value.absent(),
    this.currency = const Value.absent(),
    this.name = const Value.absent(),
    this.market = const Value.absent(),
    this.industry = const Value.absent(),
    this.region = const Value.absent(),
    this.isin = const Value.absent(),
    this.lastPrice = const Value.absent(),
    this.lastPriceAt = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetsCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required AssetType type,
    required String symbol,
    required String currency,
    this.name = const Value.absent(),
    this.market = const Value.absent(),
    this.industry = const Value.absent(),
    this.region = const Value.absent(),
    this.isin = const Value.absent(),
    this.lastPrice = const Value.absent(),
    this.lastPriceAt = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       type = Value(type),
       symbol = Value(symbol),
       currency = Value(currency);
  static Insertable<AssetRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? symbol,
    Expression<String>? currency,
    Expression<String>? name,
    Expression<String>? market,
    Expression<String>? industry,
    Expression<String>? region,
    Expression<String>? isin,
    Expression<String>? lastPrice,
    Expression<DateTime>? lastPriceAt,
    Expression<String>? logoUrl,
    Expression<String>? metadataJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (symbol != null) 'symbol': symbol,
      if (currency != null) 'currency': currency,
      if (name != null) 'name': name,
      if (market != null) 'market': market,
      if (industry != null) 'industry': industry,
      if (region != null) 'region': region,
      if (isin != null) 'isin': isin,
      if (lastPrice != null) 'last_price': lastPrice,
      if (lastPriceAt != null) 'last_price_at': lastPriceAt,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<AssetType>? type,
    Value<String>? symbol,
    Value<String>? currency,
    Value<String?>? name,
    Value<String?>? market,
    Value<String?>? industry,
    Value<String?>? region,
    Value<String?>? isin,
    Value<Decimal?>? lastPrice,
    Value<DateTime?>? lastPriceAt,
    Value<String?>? logoUrl,
    Value<String?>? metadataJson,
    Value<int>? rowid,
  }) {
    return AssetsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      type: type ?? this.type,
      symbol: symbol ?? this.symbol,
      currency: currency ?? this.currency,
      name: name ?? this.name,
      market: market ?? this.market,
      industry: industry ?? this.industry,
      region: region ?? this.region,
      isin: isin ?? this.isin,
      lastPrice: lastPrice ?? this.lastPrice,
      lastPriceAt: lastPriceAt ?? this.lastPriceAt,
      logoUrl: logoUrl ?? this.logoUrl,
      metadataJson: metadataJson ?? this.metadataJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $AssetsTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $AssetsTable.$convertertype.toSql(type.value),
      );
    }
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (market.present) {
      map['market'] = Variable<String>(market.value);
    }
    if (industry.present) {
      map['industry'] = Variable<String>(industry.value);
    }
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (isin.present) {
      map['isin'] = Variable<String>(isin.value);
    }
    if (lastPrice.present) {
      map['last_price'] = Variable<String>(
        $AssetsTable.$converterlastPricen.toSql(lastPrice.value),
      );
    }
    if (lastPriceAt.present) {
      map['last_price_at'] = Variable<DateTime>(lastPriceAt.value);
    }
    if (logoUrl.present) {
      map['logo_url'] = Variable<String>(logoUrl.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('symbol: $symbol, ')
          ..write('currency: $currency, ')
          ..write('name: $name, ')
          ..write('market: $market, ')
          ..write('industry: $industry, ')
          ..write('region: $region, ')
          ..write('isin: $isin, ')
          ..write('lastPrice: $lastPrice, ')
          ..write('lastPriceAt: $lastPriceAt, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, TransactionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($TransactionsTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TransactionType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TransactionType>($TransactionsTable.$convertertype);
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String> quantity =
      GeneratedColumn<String>(
        'quantity',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>($TransactionsTable.$converterquantity);
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String> price =
      GeneratedColumn<String>(
        'price',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>($TransactionsTable.$converterprice);
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tradeDateMeta = const VerificationMeta(
    'tradeDate',
  );
  @override
  late final GeneratedColumn<DateTime> tradeDate = GeneratedColumn<DateTime>(
    'trade_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _settleDateMeta = const VerificationMeta(
    'settleDate',
  );
  @override
  late final GeneratedColumn<DateTime> settleDate = GeneratedColumn<DateTime>(
    'settle_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal?, String> fee =
      GeneratedColumn<String>(
        'fee',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Decimal?>($TransactionsTable.$converterfeen);
  @override
  late final GeneratedColumnWithTypeConverter<Decimal?, String> tax =
      GeneratedColumn<String>(
        'tax',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Decimal?>($TransactionsTable.$convertertaxn);
  static const VerificationMeta _counterAccountIdMeta = const VerificationMeta(
    'counterAccountId',
  );
  @override
  late final GeneratedColumn<String> counterAccountId = GeneratedColumn<String>(
    'counter_account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lotIdMeta = const VerificationMeta('lotId');
  @override
  late final GeneratedColumn<String> lotId = GeneratedColumn<String>(
    'lot_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expenseMetadataJsonMeta =
      const VerificationMeta('expenseMetadataJson');
  @override
  late final GeneratedColumn<String> expenseMetadataJson =
      GeneratedColumn<String>(
        'expense_metadata_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _transferGroupIdMeta = const VerificationMeta(
    'transferGroupId',
  );
  @override
  late final GeneratedColumn<String> transferGroupId = GeneratedColumn<String>(
    'transfer_group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    accountId,
    assetId,
    type,
    quantity,
    price,
    currency,
    tradeDate,
    settleDate,
    fee,
    tax,
    counterAccountId,
    lotId,
    note,
    expenseMetadataJson,
    transferGroupId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransactionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('trade_date')) {
      context.handle(
        _tradeDateMeta,
        tradeDate.isAcceptableOrUnknown(data['trade_date']!, _tradeDateMeta),
      );
    } else if (isInserting) {
      context.missing(_tradeDateMeta);
    }
    if (data.containsKey('settle_date')) {
      context.handle(
        _settleDateMeta,
        settleDate.isAcceptableOrUnknown(data['settle_date']!, _settleDateMeta),
      );
    }
    if (data.containsKey('counter_account_id')) {
      context.handle(
        _counterAccountIdMeta,
        counterAccountId.isAcceptableOrUnknown(
          data['counter_account_id']!,
          _counterAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('lot_id')) {
      context.handle(
        _lotIdMeta,
        lotId.isAcceptableOrUnknown(data['lot_id']!, _lotIdMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('expense_metadata_json')) {
      context.handle(
        _expenseMetadataJsonMeta,
        expenseMetadataJson.isAcceptableOrUnknown(
          data['expense_metadata_json']!,
          _expenseMetadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('transfer_group_id')) {
      context.handle(
        _transferGroupIdMeta,
        transferGroupId.isAcceptableOrUnknown(
          data['transfer_group_id']!,
          _transferGroupIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransactionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $TransactionsTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      ),
      type: $TransactionsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      quantity: $TransactionsTable.$converterquantity.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}quantity'],
        )!,
      ),
      price: $TransactionsTable.$converterprice.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}price'],
        )!,
      ),
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      tradeDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}trade_date'],
      )!,
      settleDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}settle_date'],
      ),
      fee: $TransactionsTable.$converterfeen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}fee'],
        ),
      ),
      tax: $TransactionsTable.$convertertaxn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tax'],
        ),
      ),
      counterAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counter_account_id'],
      ),
      lotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lot_id'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      expenseMetadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expense_metadata_json'],
      ),
      transferGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_group_id'],
      ),
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<TransactionType, String> $convertertype =
      const EnumStringConverter(TransactionType.values);
  static TypeConverter<Decimal, String> $converterquantity =
      const DecimalConverter();
  static TypeConverter<Decimal, String> $converterprice =
      const DecimalConverter();
  static TypeConverter<Decimal, String> $converterfee =
      const DecimalConverter();
  static TypeConverter<Decimal?, String?> $converterfeen =
      NullAwareTypeConverter.wrap($converterfee);
  static TypeConverter<Decimal, String> $convertertax =
      const DecimalConverter();
  static TypeConverter<Decimal?, String?> $convertertaxn =
      NullAwareTypeConverter.wrap($convertertax);
}

class TransactionRow extends DataClass implements Insertable<TransactionRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String accountId;
  final String? assetId;
  final TransactionType type;
  final Decimal quantity;
  final Decimal price;
  final String currency;
  final DateTime tradeDate;
  final DateTime? settleDate;
  final Decimal? fee;
  final Decimal? tax;
  final String? counterAccountId;
  final String? lotId;
  final String? note;

  /// FIR-68: expense-specific payload (category id, tags, ...) when
  /// `type = expense`. NULL for every other transaction kind. Kept as a
  /// JSON blob for the same reason `assets.metadata_json` is — adding
  /// expense-only columns would bloat the row for the 95% of transactions
  /// that aren't expenses.
  final String? expenseMetadataJson;

  /// FIR-124: shared id linking the two legs of a transfer. Both the
  /// `transferOut` row on the source account and the matching `transferIn`
  /// row on the destination account carry the same id, so the pair can be
  /// joined, displayed and tombstoned as a single unit. NULL on every
  /// non-transfer transaction; legacy single-leg transfers from before
  /// FIR-124 also leave it NULL and are surfaced by the unbalanced-group
  /// audit query.
  final String? transferGroupId;
  const TransactionRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.accountId,
    this.assetId,
    required this.type,
    required this.quantity,
    required this.price,
    required this.currency,
    required this.tradeDate,
    this.settleDate,
    this.fee,
    this.tax,
    this.counterAccountId,
    this.lotId,
    this.note,
    this.expenseMetadataJson,
    this.transferGroupId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>(
        $TransactionsTable.$converterhlc.toSql(hlc),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || assetId != null) {
      map['asset_id'] = Variable<String>(assetId);
    }
    {
      map['type'] = Variable<String>(
        $TransactionsTable.$convertertype.toSql(type),
      );
    }
    {
      map['quantity'] = Variable<String>(
        $TransactionsTable.$converterquantity.toSql(quantity),
      );
    }
    {
      map['price'] = Variable<String>(
        $TransactionsTable.$converterprice.toSql(price),
      );
    }
    map['currency'] = Variable<String>(currency);
    map['trade_date'] = Variable<DateTime>(tradeDate);
    if (!nullToAbsent || settleDate != null) {
      map['settle_date'] = Variable<DateTime>(settleDate);
    }
    if (!nullToAbsent || fee != null) {
      map['fee'] = Variable<String>(
        $TransactionsTable.$converterfeen.toSql(fee),
      );
    }
    if (!nullToAbsent || tax != null) {
      map['tax'] = Variable<String>(
        $TransactionsTable.$convertertaxn.toSql(tax),
      );
    }
    if (!nullToAbsent || counterAccountId != null) {
      map['counter_account_id'] = Variable<String>(counterAccountId);
    }
    if (!nullToAbsent || lotId != null) {
      map['lot_id'] = Variable<String>(lotId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || expenseMetadataJson != null) {
      map['expense_metadata_json'] = Variable<String>(expenseMetadataJson);
    }
    if (!nullToAbsent || transferGroupId != null) {
      map['transfer_group_id'] = Variable<String>(transferGroupId);
    }
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      accountId: Value(accountId),
      assetId: assetId == null && nullToAbsent
          ? const Value.absent()
          : Value(assetId),
      type: Value(type),
      quantity: Value(quantity),
      price: Value(price),
      currency: Value(currency),
      tradeDate: Value(tradeDate),
      settleDate: settleDate == null && nullToAbsent
          ? const Value.absent()
          : Value(settleDate),
      fee: fee == null && nullToAbsent ? const Value.absent() : Value(fee),
      tax: tax == null && nullToAbsent ? const Value.absent() : Value(tax),
      counterAccountId: counterAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(counterAccountId),
      lotId: lotId == null && nullToAbsent
          ? const Value.absent()
          : Value(lotId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      expenseMetadataJson: expenseMetadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(expenseMetadataJson),
      transferGroupId: transferGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(transferGroupId),
    );
  }

  factory TransactionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      assetId: serializer.fromJson<String?>(json['assetId']),
      type: serializer.fromJson<TransactionType>(json['type']),
      quantity: serializer.fromJson<Decimal>(json['quantity']),
      price: serializer.fromJson<Decimal>(json['price']),
      currency: serializer.fromJson<String>(json['currency']),
      tradeDate: serializer.fromJson<DateTime>(json['tradeDate']),
      settleDate: serializer.fromJson<DateTime?>(json['settleDate']),
      fee: serializer.fromJson<Decimal?>(json['fee']),
      tax: serializer.fromJson<Decimal?>(json['tax']),
      counterAccountId: serializer.fromJson<String?>(json['counterAccountId']),
      lotId: serializer.fromJson<String?>(json['lotId']),
      note: serializer.fromJson<String?>(json['note']),
      expenseMetadataJson: serializer.fromJson<String?>(
        json['expenseMetadataJson'],
      ),
      transferGroupId: serializer.fromJson<String?>(json['transferGroupId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String>(accountId),
      'assetId': serializer.toJson<String?>(assetId),
      'type': serializer.toJson<TransactionType>(type),
      'quantity': serializer.toJson<Decimal>(quantity),
      'price': serializer.toJson<Decimal>(price),
      'currency': serializer.toJson<String>(currency),
      'tradeDate': serializer.toJson<DateTime>(tradeDate),
      'settleDate': serializer.toJson<DateTime?>(settleDate),
      'fee': serializer.toJson<Decimal?>(fee),
      'tax': serializer.toJson<Decimal?>(tax),
      'counterAccountId': serializer.toJson<String?>(counterAccountId),
      'lotId': serializer.toJson<String?>(lotId),
      'note': serializer.toJson<String?>(note),
      'expenseMetadataJson': serializer.toJson<String?>(expenseMetadataJson),
      'transferGroupId': serializer.toJson<String?>(transferGroupId),
    };
  }

  TransactionRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? accountId,
    Value<String?> assetId = const Value.absent(),
    TransactionType? type,
    Decimal? quantity,
    Decimal? price,
    String? currency,
    DateTime? tradeDate,
    Value<DateTime?> settleDate = const Value.absent(),
    Value<Decimal?> fee = const Value.absent(),
    Value<Decimal?> tax = const Value.absent(),
    Value<String?> counterAccountId = const Value.absent(),
    Value<String?> lotId = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<String?> expenseMetadataJson = const Value.absent(),
    Value<String?> transferGroupId = const Value.absent(),
  }) => TransactionRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    assetId: assetId.present ? assetId.value : this.assetId,
    type: type ?? this.type,
    quantity: quantity ?? this.quantity,
    price: price ?? this.price,
    currency: currency ?? this.currency,
    tradeDate: tradeDate ?? this.tradeDate,
    settleDate: settleDate.present ? settleDate.value : this.settleDate,
    fee: fee.present ? fee.value : this.fee,
    tax: tax.present ? tax.value : this.tax,
    counterAccountId: counterAccountId.present
        ? counterAccountId.value
        : this.counterAccountId,
    lotId: lotId.present ? lotId.value : this.lotId,
    note: note.present ? note.value : this.note,
    expenseMetadataJson: expenseMetadataJson.present
        ? expenseMetadataJson.value
        : this.expenseMetadataJson,
    transferGroupId: transferGroupId.present
        ? transferGroupId.value
        : this.transferGroupId,
  );
  TransactionRow copyWithCompanion(TransactionsCompanion data) {
    return TransactionRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      type: data.type.present ? data.type.value : this.type,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      price: data.price.present ? data.price.value : this.price,
      currency: data.currency.present ? data.currency.value : this.currency,
      tradeDate: data.tradeDate.present ? data.tradeDate.value : this.tradeDate,
      settleDate: data.settleDate.present
          ? data.settleDate.value
          : this.settleDate,
      fee: data.fee.present ? data.fee.value : this.fee,
      tax: data.tax.present ? data.tax.value : this.tax,
      counterAccountId: data.counterAccountId.present
          ? data.counterAccountId.value
          : this.counterAccountId,
      lotId: data.lotId.present ? data.lotId.value : this.lotId,
      note: data.note.present ? data.note.value : this.note,
      expenseMetadataJson: data.expenseMetadataJson.present
          ? data.expenseMetadataJson.value
          : this.expenseMetadataJson,
      transferGroupId: data.transferGroupId.present
          ? data.transferGroupId.value
          : this.transferGroupId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('assetId: $assetId, ')
          ..write('type: $type, ')
          ..write('quantity: $quantity, ')
          ..write('price: $price, ')
          ..write('currency: $currency, ')
          ..write('tradeDate: $tradeDate, ')
          ..write('settleDate: $settleDate, ')
          ..write('fee: $fee, ')
          ..write('tax: $tax, ')
          ..write('counterAccountId: $counterAccountId, ')
          ..write('lotId: $lotId, ')
          ..write('note: $note, ')
          ..write('expenseMetadataJson: $expenseMetadataJson, ')
          ..write('transferGroupId: $transferGroupId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    accountId,
    assetId,
    type,
    quantity,
    price,
    currency,
    tradeDate,
    settleDate,
    fee,
    tax,
    counterAccountId,
    lotId,
    note,
    expenseMetadataJson,
    transferGroupId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.assetId == this.assetId &&
          other.type == this.type &&
          other.quantity == this.quantity &&
          other.price == this.price &&
          other.currency == this.currency &&
          other.tradeDate == this.tradeDate &&
          other.settleDate == this.settleDate &&
          other.fee == this.fee &&
          other.tax == this.tax &&
          other.counterAccountId == this.counterAccountId &&
          other.lotId == this.lotId &&
          other.note == this.note &&
          other.expenseMetadataJson == this.expenseMetadataJson &&
          other.transferGroupId == this.transferGroupId);
}

class TransactionsCompanion extends UpdateCompanion<TransactionRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> accountId;
  final Value<String?> assetId;
  final Value<TransactionType> type;
  final Value<Decimal> quantity;
  final Value<Decimal> price;
  final Value<String> currency;
  final Value<DateTime> tradeDate;
  final Value<DateTime?> settleDate;
  final Value<Decimal?> fee;
  final Value<Decimal?> tax;
  final Value<String?> counterAccountId;
  final Value<String?> lotId;
  final Value<String?> note;
  final Value<String?> expenseMetadataJson;
  final Value<String?> transferGroupId;
  final Value<int> rowid;
  const TransactionsCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.type = const Value.absent(),
    this.quantity = const Value.absent(),
    this.price = const Value.absent(),
    this.currency = const Value.absent(),
    this.tradeDate = const Value.absent(),
    this.settleDate = const Value.absent(),
    this.fee = const Value.absent(),
    this.tax = const Value.absent(),
    this.counterAccountId = const Value.absent(),
    this.lotId = const Value.absent(),
    this.note = const Value.absent(),
    this.expenseMetadataJson = const Value.absent(),
    this.transferGroupId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionsCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String accountId,
    this.assetId = const Value.absent(),
    required TransactionType type,
    required Decimal quantity,
    required Decimal price,
    required String currency,
    required DateTime tradeDate,
    this.settleDate = const Value.absent(),
    this.fee = const Value.absent(),
    this.tax = const Value.absent(),
    this.counterAccountId = const Value.absent(),
    this.lotId = const Value.absent(),
    this.note = const Value.absent(),
    this.expenseMetadataJson = const Value.absent(),
    this.transferGroupId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       accountId = Value(accountId),
       type = Value(type),
       quantity = Value(quantity),
       price = Value(price),
       currency = Value(currency),
       tradeDate = Value(tradeDate);
  static Insertable<TransactionRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? assetId,
    Expression<String>? type,
    Expression<String>? quantity,
    Expression<String>? price,
    Expression<String>? currency,
    Expression<DateTime>? tradeDate,
    Expression<DateTime>? settleDate,
    Expression<String>? fee,
    Expression<String>? tax,
    Expression<String>? counterAccountId,
    Expression<String>? lotId,
    Expression<String>? note,
    Expression<String>? expenseMetadataJson,
    Expression<String>? transferGroupId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (assetId != null) 'asset_id': assetId,
      if (type != null) 'type': type,
      if (quantity != null) 'quantity': quantity,
      if (price != null) 'price': price,
      if (currency != null) 'currency': currency,
      if (tradeDate != null) 'trade_date': tradeDate,
      if (settleDate != null) 'settle_date': settleDate,
      if (fee != null) 'fee': fee,
      if (tax != null) 'tax': tax,
      if (counterAccountId != null) 'counter_account_id': counterAccountId,
      if (lotId != null) 'lot_id': lotId,
      if (note != null) 'note': note,
      if (expenseMetadataJson != null)
        'expense_metadata_json': expenseMetadataJson,
      if (transferGroupId != null) 'transfer_group_id': transferGroupId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? accountId,
    Value<String?>? assetId,
    Value<TransactionType>? type,
    Value<Decimal>? quantity,
    Value<Decimal>? price,
    Value<String>? currency,
    Value<DateTime>? tradeDate,
    Value<DateTime?>? settleDate,
    Value<Decimal?>? fee,
    Value<Decimal?>? tax,
    Value<String?>? counterAccountId,
    Value<String?>? lotId,
    Value<String?>? note,
    Value<String?>? expenseMetadataJson,
    Value<String?>? transferGroupId,
    Value<int>? rowid,
  }) {
    return TransactionsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      assetId: assetId ?? this.assetId,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      tradeDate: tradeDate ?? this.tradeDate,
      settleDate: settleDate ?? this.settleDate,
      fee: fee ?? this.fee,
      tax: tax ?? this.tax,
      counterAccountId: counterAccountId ?? this.counterAccountId,
      lotId: lotId ?? this.lotId,
      note: note ?? this.note,
      expenseMetadataJson: expenseMetadataJson ?? this.expenseMetadataJson,
      transferGroupId: transferGroupId ?? this.transferGroupId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $TransactionsTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $TransactionsTable.$convertertype.toSql(type.value),
      );
    }
    if (quantity.present) {
      map['quantity'] = Variable<String>(
        $TransactionsTable.$converterquantity.toSql(quantity.value),
      );
    }
    if (price.present) {
      map['price'] = Variable<String>(
        $TransactionsTable.$converterprice.toSql(price.value),
      );
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (tradeDate.present) {
      map['trade_date'] = Variable<DateTime>(tradeDate.value);
    }
    if (settleDate.present) {
      map['settle_date'] = Variable<DateTime>(settleDate.value);
    }
    if (fee.present) {
      map['fee'] = Variable<String>(
        $TransactionsTable.$converterfeen.toSql(fee.value),
      );
    }
    if (tax.present) {
      map['tax'] = Variable<String>(
        $TransactionsTable.$convertertaxn.toSql(tax.value),
      );
    }
    if (counterAccountId.present) {
      map['counter_account_id'] = Variable<String>(counterAccountId.value);
    }
    if (lotId.present) {
      map['lot_id'] = Variable<String>(lotId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (expenseMetadataJson.present) {
      map['expense_metadata_json'] = Variable<String>(
        expenseMetadataJson.value,
      );
    }
    if (transferGroupId.present) {
      map['transfer_group_id'] = Variable<String>(transferGroupId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('assetId: $assetId, ')
          ..write('type: $type, ')
          ..write('quantity: $quantity, ')
          ..write('price: $price, ')
          ..write('currency: $currency, ')
          ..write('tradeDate: $tradeDate, ')
          ..write('settleDate: $settleDate, ')
          ..write('fee: $fee, ')
          ..write('tax: $tax, ')
          ..write('counterAccountId: $counterAccountId, ')
          ..write('lotId: $lotId, ')
          ..write('note: $note, ')
          ..write('expenseMetadataJson: $expenseMetadataJson, ')
          ..write('transferGroupId: $transferGroupId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LiabilitiesTable extends Liabilities
    with TableInfo<$LiabilitiesTable, LiabilityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LiabilitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($LiabilitiesTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LiabilityType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LiabilityType>($LiabilitiesTable.$convertertype);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String> principal =
      GeneratedColumn<String>(
        'principal',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>($LiabilitiesTable.$converterprincipal);
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String> interestRate =
      GeneratedColumn<String>(
        'interest_rate',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>($LiabilitiesTable.$converterinterestRate);
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<RepaymentMethod, String>
  paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: Constant(RepaymentMethod.equalInstallment.name),
  ).withConverter<RepaymentMethod>($LiabilitiesTable.$converterpaymentMethod);
  @override
  late final GeneratedColumnWithTypeConverter<LiabilityRateType, String>
  rateType = GeneratedColumn<String>(
    'rate_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: Constant(LiabilityRateType.fixed.name),
  ).withConverter<LiabilityRateType>($LiabilitiesTable.$converterrateType);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _termMonthsMeta = const VerificationMeta(
    'termMonths',
  );
  @override
  late final GeneratedColumn<int> termMonths = GeneratedColumn<int>(
    'term_months',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal?, String> monthlyPayment =
      GeneratedColumn<String>(
        'monthly_payment',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Decimal?>($LiabilitiesTable.$convertermonthlyPaymentn);
  static const VerificationMeta _statementDayMeta = const VerificationMeta(
    'statementDay',
  );
  @override
  late final GeneratedColumn<int> statementDay = GeneratedColumn<int>(
    'statement_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentDueDayMeta = const VerificationMeta(
    'paymentDueDay',
  );
  @override
  late final GeneratedColumn<int> paymentDueDay = GeneratedColumn<int>(
    'payment_due_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    type,
    name,
    principal,
    interestRate,
    currency,
    paymentMethod,
    rateType,
    accountId,
    startDate,
    endDate,
    termMonths,
    monthlyPayment,
    statementDay,
    paymentDueDay,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'liabilities';
  @override
  VerificationContext validateIntegrity(
    Insertable<LiabilityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('term_months')) {
      context.handle(
        _termMonthsMeta,
        termMonths.isAcceptableOrUnknown(data['term_months']!, _termMonthsMeta),
      );
    }
    if (data.containsKey('statement_day')) {
      context.handle(
        _statementDayMeta,
        statementDay.isAcceptableOrUnknown(
          data['statement_day']!,
          _statementDayMeta,
        ),
      );
    }
    if (data.containsKey('payment_due_day')) {
      context.handle(
        _paymentDueDayMeta,
        paymentDueDay.isAcceptableOrUnknown(
          data['payment_due_day']!,
          _paymentDueDayMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LiabilityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LiabilityRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $LiabilitiesTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: $LiabilitiesTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      principal: $LiabilitiesTable.$converterprincipal.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}principal'],
        )!,
      ),
      interestRate: $LiabilitiesTable.$converterinterestRate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}interest_rate'],
        )!,
      ),
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      paymentMethod: $LiabilitiesTable.$converterpaymentMethod.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}payment_method'],
        )!,
      ),
      rateType: $LiabilitiesTable.$converterrateType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}rate_type'],
        )!,
      ),
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      ),
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
      termMonths: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}term_months'],
      ),
      monthlyPayment: $LiabilitiesTable.$convertermonthlyPaymentn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}monthly_payment'],
        ),
      ),
      statementDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}statement_day'],
      ),
      paymentDueDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payment_due_day'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $LiabilitiesTable createAlias(String alias) {
    return $LiabilitiesTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<LiabilityType, String> $convertertype =
      const EnumStringConverter(LiabilityType.values);
  static TypeConverter<Decimal, String> $converterprincipal =
      const DecimalConverter();
  static TypeConverter<Decimal, String> $converterinterestRate =
      const DecimalConverter();
  static TypeConverter<RepaymentMethod, String> $converterpaymentMethod =
      const EnumStringConverter(RepaymentMethod.values);
  static TypeConverter<LiabilityRateType, String> $converterrateType =
      const EnumStringConverter(LiabilityRateType.values);
  static TypeConverter<Decimal, String> $convertermonthlyPayment =
      const DecimalConverter();
  static TypeConverter<Decimal?, String?> $convertermonthlyPaymentn =
      NullAwareTypeConverter.wrap($convertermonthlyPayment);
}

class LiabilityRow extends DataClass implements Insertable<LiabilityRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final LiabilityType type;
  final String name;
  final Decimal principal;
  final Decimal interestRate;
  final String currency;
  final RepaymentMethod paymentMethod;
  final LiabilityRateType rateType;
  final String? accountId;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? termMonths;
  final Decimal? monthlyPayment;
  final int? statementDay;
  final int? paymentDueDay;
  final String? note;
  const LiabilityRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.type,
    required this.name,
    required this.principal,
    required this.interestRate,
    required this.currency,
    required this.paymentMethod,
    required this.rateType,
    this.accountId,
    this.startDate,
    this.endDate,
    this.termMonths,
    this.monthlyPayment,
    this.statementDay,
    this.paymentDueDay,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($LiabilitiesTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    {
      map['type'] = Variable<String>(
        $LiabilitiesTable.$convertertype.toSql(type),
      );
    }
    map['name'] = Variable<String>(name);
    {
      map['principal'] = Variable<String>(
        $LiabilitiesTable.$converterprincipal.toSql(principal),
      );
    }
    {
      map['interest_rate'] = Variable<String>(
        $LiabilitiesTable.$converterinterestRate.toSql(interestRate),
      );
    }
    map['currency'] = Variable<String>(currency);
    {
      map['payment_method'] = Variable<String>(
        $LiabilitiesTable.$converterpaymentMethod.toSql(paymentMethod),
      );
    }
    {
      map['rate_type'] = Variable<String>(
        $LiabilitiesTable.$converterrateType.toSql(rateType),
      );
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    if (!nullToAbsent || startDate != null) {
      map['start_date'] = Variable<DateTime>(startDate);
    }
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    if (!nullToAbsent || termMonths != null) {
      map['term_months'] = Variable<int>(termMonths);
    }
    if (!nullToAbsent || monthlyPayment != null) {
      map['monthly_payment'] = Variable<String>(
        $LiabilitiesTable.$convertermonthlyPaymentn.toSql(monthlyPayment),
      );
    }
    if (!nullToAbsent || statementDay != null) {
      map['statement_day'] = Variable<int>(statementDay);
    }
    if (!nullToAbsent || paymentDueDay != null) {
      map['payment_due_day'] = Variable<int>(paymentDueDay);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  LiabilitiesCompanion toCompanion(bool nullToAbsent) {
    return LiabilitiesCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      type: Value(type),
      name: Value(name),
      principal: Value(principal),
      interestRate: Value(interestRate),
      currency: Value(currency),
      paymentMethod: Value(paymentMethod),
      rateType: Value(rateType),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      startDate: startDate == null && nullToAbsent
          ? const Value.absent()
          : Value(startDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      termMonths: termMonths == null && nullToAbsent
          ? const Value.absent()
          : Value(termMonths),
      monthlyPayment: monthlyPayment == null && nullToAbsent
          ? const Value.absent()
          : Value(monthlyPayment),
      statementDay: statementDay == null && nullToAbsent
          ? const Value.absent()
          : Value(statementDay),
      paymentDueDay: paymentDueDay == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentDueDay),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory LiabilityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LiabilityRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<LiabilityType>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      principal: serializer.fromJson<Decimal>(json['principal']),
      interestRate: serializer.fromJson<Decimal>(json['interestRate']),
      currency: serializer.fromJson<String>(json['currency']),
      paymentMethod: serializer.fromJson<RepaymentMethod>(
        json['paymentMethod'],
      ),
      rateType: serializer.fromJson<LiabilityRateType>(json['rateType']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      startDate: serializer.fromJson<DateTime?>(json['startDate']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
      termMonths: serializer.fromJson<int?>(json['termMonths']),
      monthlyPayment: serializer.fromJson<Decimal?>(json['monthlyPayment']),
      statementDay: serializer.fromJson<int?>(json['statementDay']),
      paymentDueDay: serializer.fromJson<int?>(json['paymentDueDay']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<LiabilityType>(type),
      'name': serializer.toJson<String>(name),
      'principal': serializer.toJson<Decimal>(principal),
      'interestRate': serializer.toJson<Decimal>(interestRate),
      'currency': serializer.toJson<String>(currency),
      'paymentMethod': serializer.toJson<RepaymentMethod>(paymentMethod),
      'rateType': serializer.toJson<LiabilityRateType>(rateType),
      'accountId': serializer.toJson<String?>(accountId),
      'startDate': serializer.toJson<DateTime?>(startDate),
      'endDate': serializer.toJson<DateTime?>(endDate),
      'termMonths': serializer.toJson<int?>(termMonths),
      'monthlyPayment': serializer.toJson<Decimal?>(monthlyPayment),
      'statementDay': serializer.toJson<int?>(statementDay),
      'paymentDueDay': serializer.toJson<int?>(paymentDueDay),
      'note': serializer.toJson<String?>(note),
    };
  }

  LiabilityRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    LiabilityType? type,
    String? name,
    Decimal? principal,
    Decimal? interestRate,
    String? currency,
    RepaymentMethod? paymentMethod,
    LiabilityRateType? rateType,
    Value<String?> accountId = const Value.absent(),
    Value<DateTime?> startDate = const Value.absent(),
    Value<DateTime?> endDate = const Value.absent(),
    Value<int?> termMonths = const Value.absent(),
    Value<Decimal?> monthlyPayment = const Value.absent(),
    Value<int?> statementDay = const Value.absent(),
    Value<int?> paymentDueDay = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) => LiabilityRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    type: type ?? this.type,
    name: name ?? this.name,
    principal: principal ?? this.principal,
    interestRate: interestRate ?? this.interestRate,
    currency: currency ?? this.currency,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    rateType: rateType ?? this.rateType,
    accountId: accountId.present ? accountId.value : this.accountId,
    startDate: startDate.present ? startDate.value : this.startDate,
    endDate: endDate.present ? endDate.value : this.endDate,
    termMonths: termMonths.present ? termMonths.value : this.termMonths,
    monthlyPayment: monthlyPayment.present
        ? monthlyPayment.value
        : this.monthlyPayment,
    statementDay: statementDay.present ? statementDay.value : this.statementDay,
    paymentDueDay: paymentDueDay.present
        ? paymentDueDay.value
        : this.paymentDueDay,
    note: note.present ? note.value : this.note,
  );
  LiabilityRow copyWithCompanion(LiabilitiesCompanion data) {
    return LiabilityRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      principal: data.principal.present ? data.principal.value : this.principal,
      interestRate: data.interestRate.present
          ? data.interestRate.value
          : this.interestRate,
      currency: data.currency.present ? data.currency.value : this.currency,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      rateType: data.rateType.present ? data.rateType.value : this.rateType,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      termMonths: data.termMonths.present
          ? data.termMonths.value
          : this.termMonths,
      monthlyPayment: data.monthlyPayment.present
          ? data.monthlyPayment.value
          : this.monthlyPayment,
      statementDay: data.statementDay.present
          ? data.statementDay.value
          : this.statementDay,
      paymentDueDay: data.paymentDueDay.present
          ? data.paymentDueDay.value
          : this.paymentDueDay,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LiabilityRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('principal: $principal, ')
          ..write('interestRate: $interestRate, ')
          ..write('currency: $currency, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('rateType: $rateType, ')
          ..write('accountId: $accountId, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('termMonths: $termMonths, ')
          ..write('monthlyPayment: $monthlyPayment, ')
          ..write('statementDay: $statementDay, ')
          ..write('paymentDueDay: $paymentDueDay, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    type,
    name,
    principal,
    interestRate,
    currency,
    paymentMethod,
    rateType,
    accountId,
    startDate,
    endDate,
    termMonths,
    monthlyPayment,
    statementDay,
    paymentDueDay,
    note,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LiabilityRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.type == this.type &&
          other.name == this.name &&
          other.principal == this.principal &&
          other.interestRate == this.interestRate &&
          other.currency == this.currency &&
          other.paymentMethod == this.paymentMethod &&
          other.rateType == this.rateType &&
          other.accountId == this.accountId &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.termMonths == this.termMonths &&
          other.monthlyPayment == this.monthlyPayment &&
          other.statementDay == this.statementDay &&
          other.paymentDueDay == this.paymentDueDay &&
          other.note == this.note);
}

class LiabilitiesCompanion extends UpdateCompanion<LiabilityRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<LiabilityType> type;
  final Value<String> name;
  final Value<Decimal> principal;
  final Value<Decimal> interestRate;
  final Value<String> currency;
  final Value<RepaymentMethod> paymentMethod;
  final Value<LiabilityRateType> rateType;
  final Value<String?> accountId;
  final Value<DateTime?> startDate;
  final Value<DateTime?> endDate;
  final Value<int?> termMonths;
  final Value<Decimal?> monthlyPayment;
  final Value<int?> statementDay;
  final Value<int?> paymentDueDay;
  final Value<String?> note;
  final Value<int> rowid;
  const LiabilitiesCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.principal = const Value.absent(),
    this.interestRate = const Value.absent(),
    this.currency = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.rateType = const Value.absent(),
    this.accountId = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.termMonths = const Value.absent(),
    this.monthlyPayment = const Value.absent(),
    this.statementDay = const Value.absent(),
    this.paymentDueDay = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LiabilitiesCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required LiabilityType type,
    required String name,
    required Decimal principal,
    required Decimal interestRate,
    required String currency,
    this.paymentMethod = const Value.absent(),
    this.rateType = const Value.absent(),
    this.accountId = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.termMonths = const Value.absent(),
    this.monthlyPayment = const Value.absent(),
    this.statementDay = const Value.absent(),
    this.paymentDueDay = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       type = Value(type),
       name = Value(name),
       principal = Value(principal),
       interestRate = Value(interestRate),
       currency = Value(currency);
  static Insertable<LiabilityRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? principal,
    Expression<String>? interestRate,
    Expression<String>? currency,
    Expression<String>? paymentMethod,
    Expression<String>? rateType,
    Expression<String>? accountId,
    Expression<DateTime>? startDate,
    Expression<DateTime>? endDate,
    Expression<int>? termMonths,
    Expression<String>? monthlyPayment,
    Expression<int>? statementDay,
    Expression<int>? paymentDueDay,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (principal != null) 'principal': principal,
      if (interestRate != null) 'interest_rate': interestRate,
      if (currency != null) 'currency': currency,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (rateType != null) 'rate_type': rateType,
      if (accountId != null) 'account_id': accountId,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (termMonths != null) 'term_months': termMonths,
      if (monthlyPayment != null) 'monthly_payment': monthlyPayment,
      if (statementDay != null) 'statement_day': statementDay,
      if (paymentDueDay != null) 'payment_due_day': paymentDueDay,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LiabilitiesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<LiabilityType>? type,
    Value<String>? name,
    Value<Decimal>? principal,
    Value<Decimal>? interestRate,
    Value<String>? currency,
    Value<RepaymentMethod>? paymentMethod,
    Value<LiabilityRateType>? rateType,
    Value<String?>? accountId,
    Value<DateTime?>? startDate,
    Value<DateTime?>? endDate,
    Value<int?>? termMonths,
    Value<Decimal?>? monthlyPayment,
    Value<int?>? statementDay,
    Value<int?>? paymentDueDay,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return LiabilitiesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      principal: principal ?? this.principal,
      interestRate: interestRate ?? this.interestRate,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      rateType: rateType ?? this.rateType,
      accountId: accountId ?? this.accountId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      termMonths: termMonths ?? this.termMonths,
      monthlyPayment: monthlyPayment ?? this.monthlyPayment,
      statementDay: statementDay ?? this.statementDay,
      paymentDueDay: paymentDueDay ?? this.paymentDueDay,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $LiabilitiesTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $LiabilitiesTable.$convertertype.toSql(type.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (principal.present) {
      map['principal'] = Variable<String>(
        $LiabilitiesTable.$converterprincipal.toSql(principal.value),
      );
    }
    if (interestRate.present) {
      map['interest_rate'] = Variable<String>(
        $LiabilitiesTable.$converterinterestRate.toSql(interestRate.value),
      );
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(
        $LiabilitiesTable.$converterpaymentMethod.toSql(paymentMethod.value),
      );
    }
    if (rateType.present) {
      map['rate_type'] = Variable<String>(
        $LiabilitiesTable.$converterrateType.toSql(rateType.value),
      );
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    if (termMonths.present) {
      map['term_months'] = Variable<int>(termMonths.value);
    }
    if (monthlyPayment.present) {
      map['monthly_payment'] = Variable<String>(
        $LiabilitiesTable.$convertermonthlyPaymentn.toSql(monthlyPayment.value),
      );
    }
    if (statementDay.present) {
      map['statement_day'] = Variable<int>(statementDay.value);
    }
    if (paymentDueDay.present) {
      map['payment_due_day'] = Variable<int>(paymentDueDay.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LiabilitiesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('principal: $principal, ')
          ..write('interestRate: $interestRate, ')
          ..write('currency: $currency, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('rateType: $rateType, ')
          ..write('accountId: $accountId, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('termMonths: $termMonths, ')
          ..write('monthlyPayment: $monthlyPayment, ')
          ..write('statementDay: $statementDay, ')
          ..write('paymentDueDay: $paymentDueDay, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AmortizationEntriesTable extends AmortizationEntries
    with TableInfo<$AmortizationEntriesTable, AmortizationEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AmortizationEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($AmortizationEntriesTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _liabilityIdMeta = const VerificationMeta(
    'liabilityId',
  );
  @override
  late final GeneratedColumn<String> liabilityId = GeneratedColumn<String>(
    'liability_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodIndexMeta = const VerificationMeta(
    'periodIndex',
  );
  @override
  late final GeneratedColumn<int> periodIndex = GeneratedColumn<int>(
    'period_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String>
  principalPayment =
      GeneratedColumn<String>(
        'principal_payment',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>(
        $AmortizationEntriesTable.$converterprincipalPayment,
      );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String> interestPayment =
      GeneratedColumn<String>(
        'interest_payment',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>(
        $AmortizationEntriesTable.$converterinterestPayment,
      );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String>
  remainingBalance =
      GeneratedColumn<String>(
        'remaining_balance',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>(
        $AmortizationEntriesTable.$converterremainingBalance,
      );
  static const VerificationMeta _paidAtMeta = const VerificationMeta('paidAt');
  @override
  late final GeneratedColumn<DateTime> paidAt = GeneratedColumn<DateTime>(
    'paid_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    liabilityId,
    periodIndex,
    dueDate,
    principalPayment,
    interestPayment,
    remainingBalance,
    paidAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'amortization_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<AmortizationEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('liability_id')) {
      context.handle(
        _liabilityIdMeta,
        liabilityId.isAcceptableOrUnknown(
          data['liability_id']!,
          _liabilityIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_liabilityIdMeta);
    }
    if (data.containsKey('period_index')) {
      context.handle(
        _periodIndexMeta,
        periodIndex.isAcceptableOrUnknown(
          data['period_index']!,
          _periodIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodIndexMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    } else if (isInserting) {
      context.missing(_dueDateMeta);
    }
    if (data.containsKey('paid_at')) {
      context.handle(
        _paidAtMeta,
        paidAt.isAcceptableOrUnknown(data['paid_at']!, _paidAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AmortizationEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AmortizationEntryRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $AmortizationEntriesTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      liabilityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}liability_id'],
      )!,
      periodIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period_index'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      )!,
      principalPayment: $AmortizationEntriesTable.$converterprincipalPayment
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}principal_payment'],
            )!,
          ),
      interestPayment: $AmortizationEntriesTable.$converterinterestPayment
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}interest_payment'],
            )!,
          ),
      remainingBalance: $AmortizationEntriesTable.$converterremainingBalance
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}remaining_balance'],
            )!,
          ),
      paidAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paid_at'],
      ),
    );
  }

  @override
  $AmortizationEntriesTable createAlias(String alias) {
    return $AmortizationEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<Decimal, String> $converterprincipalPayment =
      const DecimalConverter();
  static TypeConverter<Decimal, String> $converterinterestPayment =
      const DecimalConverter();
  static TypeConverter<Decimal, String> $converterremainingBalance =
      const DecimalConverter();
}

class AmortizationEntryRow extends DataClass
    implements Insertable<AmortizationEntryRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String liabilityId;
  final int periodIndex;
  final DateTime dueDate;
  final Decimal principalPayment;
  final Decimal interestPayment;
  final Decimal remainingBalance;
  final DateTime? paidAt;
  const AmortizationEntryRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.liabilityId,
    required this.periodIndex,
    required this.dueDate,
    required this.principalPayment,
    required this.interestPayment,
    required this.remainingBalance,
    this.paidAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>(
        $AmortizationEntriesTable.$converterhlc.toSql(hlc),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['liability_id'] = Variable<String>(liabilityId);
    map['period_index'] = Variable<int>(periodIndex);
    map['due_date'] = Variable<DateTime>(dueDate);
    {
      map['principal_payment'] = Variable<String>(
        $AmortizationEntriesTable.$converterprincipalPayment.toSql(
          principalPayment,
        ),
      );
    }
    {
      map['interest_payment'] = Variable<String>(
        $AmortizationEntriesTable.$converterinterestPayment.toSql(
          interestPayment,
        ),
      );
    }
    {
      map['remaining_balance'] = Variable<String>(
        $AmortizationEntriesTable.$converterremainingBalance.toSql(
          remainingBalance,
        ),
      );
    }
    if (!nullToAbsent || paidAt != null) {
      map['paid_at'] = Variable<DateTime>(paidAt);
    }
    return map;
  }

  AmortizationEntriesCompanion toCompanion(bool nullToAbsent) {
    return AmortizationEntriesCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      liabilityId: Value(liabilityId),
      periodIndex: Value(periodIndex),
      dueDate: Value(dueDate),
      principalPayment: Value(principalPayment),
      interestPayment: Value(interestPayment),
      remainingBalance: Value(remainingBalance),
      paidAt: paidAt == null && nullToAbsent
          ? const Value.absent()
          : Value(paidAt),
    );
  }

  factory AmortizationEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AmortizationEntryRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      liabilityId: serializer.fromJson<String>(json['liabilityId']),
      periodIndex: serializer.fromJson<int>(json['periodIndex']),
      dueDate: serializer.fromJson<DateTime>(json['dueDate']),
      principalPayment: serializer.fromJson<Decimal>(json['principalPayment']),
      interestPayment: serializer.fromJson<Decimal>(json['interestPayment']),
      remainingBalance: serializer.fromJson<Decimal>(json['remainingBalance']),
      paidAt: serializer.fromJson<DateTime?>(json['paidAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'liabilityId': serializer.toJson<String>(liabilityId),
      'periodIndex': serializer.toJson<int>(periodIndex),
      'dueDate': serializer.toJson<DateTime>(dueDate),
      'principalPayment': serializer.toJson<Decimal>(principalPayment),
      'interestPayment': serializer.toJson<Decimal>(interestPayment),
      'remainingBalance': serializer.toJson<Decimal>(remainingBalance),
      'paidAt': serializer.toJson<DateTime?>(paidAt),
    };
  }

  AmortizationEntryRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? liabilityId,
    int? periodIndex,
    DateTime? dueDate,
    Decimal? principalPayment,
    Decimal? interestPayment,
    Decimal? remainingBalance,
    Value<DateTime?> paidAt = const Value.absent(),
  }) => AmortizationEntryRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    liabilityId: liabilityId ?? this.liabilityId,
    periodIndex: periodIndex ?? this.periodIndex,
    dueDate: dueDate ?? this.dueDate,
    principalPayment: principalPayment ?? this.principalPayment,
    interestPayment: interestPayment ?? this.interestPayment,
    remainingBalance: remainingBalance ?? this.remainingBalance,
    paidAt: paidAt.present ? paidAt.value : this.paidAt,
  );
  AmortizationEntryRow copyWithCompanion(AmortizationEntriesCompanion data) {
    return AmortizationEntryRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      liabilityId: data.liabilityId.present
          ? data.liabilityId.value
          : this.liabilityId,
      periodIndex: data.periodIndex.present
          ? data.periodIndex.value
          : this.periodIndex,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      principalPayment: data.principalPayment.present
          ? data.principalPayment.value
          : this.principalPayment,
      interestPayment: data.interestPayment.present
          ? data.interestPayment.value
          : this.interestPayment,
      remainingBalance: data.remainingBalance.present
          ? data.remainingBalance.value
          : this.remainingBalance,
      paidAt: data.paidAt.present ? data.paidAt.value : this.paidAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AmortizationEntryRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('liabilityId: $liabilityId, ')
          ..write('periodIndex: $periodIndex, ')
          ..write('dueDate: $dueDate, ')
          ..write('principalPayment: $principalPayment, ')
          ..write('interestPayment: $interestPayment, ')
          ..write('remainingBalance: $remainingBalance, ')
          ..write('paidAt: $paidAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    liabilityId,
    periodIndex,
    dueDate,
    principalPayment,
    interestPayment,
    remainingBalance,
    paidAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AmortizationEntryRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.liabilityId == this.liabilityId &&
          other.periodIndex == this.periodIndex &&
          other.dueDate == this.dueDate &&
          other.principalPayment == this.principalPayment &&
          other.interestPayment == this.interestPayment &&
          other.remainingBalance == this.remainingBalance &&
          other.paidAt == this.paidAt);
}

class AmortizationEntriesCompanion
    extends UpdateCompanion<AmortizationEntryRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> liabilityId;
  final Value<int> periodIndex;
  final Value<DateTime> dueDate;
  final Value<Decimal> principalPayment;
  final Value<Decimal> interestPayment;
  final Value<Decimal> remainingBalance;
  final Value<DateTime?> paidAt;
  final Value<int> rowid;
  const AmortizationEntriesCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.liabilityId = const Value.absent(),
    this.periodIndex = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.principalPayment = const Value.absent(),
    this.interestPayment = const Value.absent(),
    this.remainingBalance = const Value.absent(),
    this.paidAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AmortizationEntriesCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String liabilityId,
    required int periodIndex,
    required DateTime dueDate,
    required Decimal principalPayment,
    required Decimal interestPayment,
    required Decimal remainingBalance,
    this.paidAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       liabilityId = Value(liabilityId),
       periodIndex = Value(periodIndex),
       dueDate = Value(dueDate),
       principalPayment = Value(principalPayment),
       interestPayment = Value(interestPayment),
       remainingBalance = Value(remainingBalance);
  static Insertable<AmortizationEntryRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? liabilityId,
    Expression<int>? periodIndex,
    Expression<DateTime>? dueDate,
    Expression<String>? principalPayment,
    Expression<String>? interestPayment,
    Expression<String>? remainingBalance,
    Expression<DateTime>? paidAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (liabilityId != null) 'liability_id': liabilityId,
      if (periodIndex != null) 'period_index': periodIndex,
      if (dueDate != null) 'due_date': dueDate,
      if (principalPayment != null) 'principal_payment': principalPayment,
      if (interestPayment != null) 'interest_payment': interestPayment,
      if (remainingBalance != null) 'remaining_balance': remainingBalance,
      if (paidAt != null) 'paid_at': paidAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AmortizationEntriesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? liabilityId,
    Value<int>? periodIndex,
    Value<DateTime>? dueDate,
    Value<Decimal>? principalPayment,
    Value<Decimal>? interestPayment,
    Value<Decimal>? remainingBalance,
    Value<DateTime?>? paidAt,
    Value<int>? rowid,
  }) {
    return AmortizationEntriesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      liabilityId: liabilityId ?? this.liabilityId,
      periodIndex: periodIndex ?? this.periodIndex,
      dueDate: dueDate ?? this.dueDate,
      principalPayment: principalPayment ?? this.principalPayment,
      interestPayment: interestPayment ?? this.interestPayment,
      remainingBalance: remainingBalance ?? this.remainingBalance,
      paidAt: paidAt ?? this.paidAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $AmortizationEntriesTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (liabilityId.present) {
      map['liability_id'] = Variable<String>(liabilityId.value);
    }
    if (periodIndex.present) {
      map['period_index'] = Variable<int>(periodIndex.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (principalPayment.present) {
      map['principal_payment'] = Variable<String>(
        $AmortizationEntriesTable.$converterprincipalPayment.toSql(
          principalPayment.value,
        ),
      );
    }
    if (interestPayment.present) {
      map['interest_payment'] = Variable<String>(
        $AmortizationEntriesTable.$converterinterestPayment.toSql(
          interestPayment.value,
        ),
      );
    }
    if (remainingBalance.present) {
      map['remaining_balance'] = Variable<String>(
        $AmortizationEntriesTable.$converterremainingBalance.toSql(
          remainingBalance.value,
        ),
      );
    }
    if (paidAt.present) {
      map['paid_at'] = Variable<DateTime>(paidAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AmortizationEntriesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('liabilityId: $liabilityId, ')
          ..write('periodIndex: $periodIndex, ')
          ..write('dueDate: $dueDate, ')
          ..write('principalPayment: $principalPayment, ')
          ..write('interestPayment: $interestPayment, ')
          ..write('remainingBalance: $remainingBalance, ')
          ..write('paidAt: $paidAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CurrenciesTable extends Currencies
    with TableInfo<$CurrenciesTable, CurrencyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CurrenciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decimalsMeta = const VerificationMeta(
    'decimals',
  );
  @override
  late final GeneratedColumn<int> decimals = GeneratedColumn<int>(
    'decimals',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [code, name, decimals, symbol];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'currencies';
  @override
  VerificationContext validateIntegrity(
    Insertable<CurrencyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('decimals')) {
      context.handle(
        _decimalsMeta,
        decimals.isAcceptableOrUnknown(data['decimals']!, _decimalsMeta),
      );
    } else if (isInserting) {
      context.missing(_decimalsMeta);
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  CurrencyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CurrencyRow(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      decimals: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}decimals'],
      )!,
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      ),
    );
  }

  @override
  $CurrenciesTable createAlias(String alias) {
    return $CurrenciesTable(attachedDatabase, alias);
  }
}

class CurrencyRow extends DataClass implements Insertable<CurrencyRow> {
  final String code;
  final String name;
  final int decimals;
  final String? symbol;
  const CurrencyRow({
    required this.code,
    required this.name,
    required this.decimals,
    this.symbol,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['decimals'] = Variable<int>(decimals);
    if (!nullToAbsent || symbol != null) {
      map['symbol'] = Variable<String>(symbol);
    }
    return map;
  }

  CurrenciesCompanion toCompanion(bool nullToAbsent) {
    return CurrenciesCompanion(
      code: Value(code),
      name: Value(name),
      decimals: Value(decimals),
      symbol: symbol == null && nullToAbsent
          ? const Value.absent()
          : Value(symbol),
    );
  }

  factory CurrencyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CurrencyRow(
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      decimals: serializer.fromJson<int>(json['decimals']),
      symbol: serializer.fromJson<String?>(json['symbol']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'decimals': serializer.toJson<int>(decimals),
      'symbol': serializer.toJson<String?>(symbol),
    };
  }

  CurrencyRow copyWith({
    String? code,
    String? name,
    int? decimals,
    Value<String?> symbol = const Value.absent(),
  }) => CurrencyRow(
    code: code ?? this.code,
    name: name ?? this.name,
    decimals: decimals ?? this.decimals,
    symbol: symbol.present ? symbol.value : this.symbol,
  );
  CurrencyRow copyWithCompanion(CurrenciesCompanion data) {
    return CurrencyRow(
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      decimals: data.decimals.present ? data.decimals.value : this.decimals,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CurrencyRow(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('decimals: $decimals, ')
          ..write('symbol: $symbol')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, name, decimals, symbol);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CurrencyRow &&
          other.code == this.code &&
          other.name == this.name &&
          other.decimals == this.decimals &&
          other.symbol == this.symbol);
}

class CurrenciesCompanion extends UpdateCompanion<CurrencyRow> {
  final Value<String> code;
  final Value<String> name;
  final Value<int> decimals;
  final Value<String?> symbol;
  final Value<int> rowid;
  const CurrenciesCompanion({
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.decimals = const Value.absent(),
    this.symbol = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CurrenciesCompanion.insert({
    required String code,
    required String name,
    required int decimals,
    this.symbol = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : code = Value(code),
       name = Value(name),
       decimals = Value(decimals);
  static Insertable<CurrencyRow> custom({
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? decimals,
    Expression<String>? symbol,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (decimals != null) 'decimals': decimals,
      if (symbol != null) 'symbol': symbol,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CurrenciesCompanion copyWith({
    Value<String>? code,
    Value<String>? name,
    Value<int>? decimals,
    Value<String?>? symbol,
    Value<int>? rowid,
  }) {
    return CurrenciesCompanion(
      code: code ?? this.code,
      name: name ?? this.name,
      decimals: decimals ?? this.decimals,
      symbol: symbol ?? this.symbol,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (decimals.present) {
      map['decimals'] = Variable<int>(decimals.value);
    }
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CurrenciesCompanion(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('decimals: $decimals, ')
          ..write('symbol: $symbol, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FxRatesTable extends FxRates with TableInfo<$FxRatesTable, FxRateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FxRatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseCurrencyMeta = const VerificationMeta(
    'baseCurrency',
  );
  @override
  late final GeneratedColumn<String> baseCurrency = GeneratedColumn<String>(
    'base_currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quoteCurrencyMeta = const VerificationMeta(
    'quoteCurrency',
  );
  @override
  late final GeneratedColumn<String> quoteCurrency = GeneratedColumn<String>(
    'quote_currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String> rate =
      GeneratedColumn<String>(
        'rate',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>($FxRatesTable.$converterrate);
  static const VerificationMeta _asOfMeta = const VerificationMeta('asOf');
  @override
  late final GeneratedColumn<DateTime> asOf = GeneratedColumn<DateTime>(
    'as_of',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    baseCurrency,
    quoteCurrency,
    rate,
    asOf,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fx_rates';
  @override
  VerificationContext validateIntegrity(
    Insertable<FxRateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('base_currency')) {
      context.handle(
        _baseCurrencyMeta,
        baseCurrency.isAcceptableOrUnknown(
          data['base_currency']!,
          _baseCurrencyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseCurrencyMeta);
    }
    if (data.containsKey('quote_currency')) {
      context.handle(
        _quoteCurrencyMeta,
        quoteCurrency.isAcceptableOrUnknown(
          data['quote_currency']!,
          _quoteCurrencyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quoteCurrencyMeta);
    }
    if (data.containsKey('as_of')) {
      context.handle(
        _asOfMeta,
        asOf.isAcceptableOrUnknown(data['as_of']!, _asOfMeta),
      );
    } else if (isInserting) {
      context.missing(_asOfMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FxRateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FxRateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      baseCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_currency'],
      )!,
      quoteCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quote_currency'],
      )!,
      rate: $FxRatesTable.$converterrate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}rate'],
        )!,
      ),
      asOf: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}as_of'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
    );
  }

  @override
  $FxRatesTable createAlias(String alias) {
    return $FxRatesTable(attachedDatabase, alias);
  }

  static TypeConverter<Decimal, String> $converterrate =
      const DecimalConverter();
}

class FxRateRow extends DataClass implements Insertable<FxRateRow> {
  final String id;
  final String baseCurrency;
  final String quoteCurrency;
  final Decimal rate;
  final DateTime asOf;
  final String? source;
  const FxRateRow({
    required this.id,
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.rate,
    required this.asOf,
    this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['base_currency'] = Variable<String>(baseCurrency);
    map['quote_currency'] = Variable<String>(quoteCurrency);
    {
      map['rate'] = Variable<String>($FxRatesTable.$converterrate.toSql(rate));
    }
    map['as_of'] = Variable<DateTime>(asOf);
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    return map;
  }

  FxRatesCompanion toCompanion(bool nullToAbsent) {
    return FxRatesCompanion(
      id: Value(id),
      baseCurrency: Value(baseCurrency),
      quoteCurrency: Value(quoteCurrency),
      rate: Value(rate),
      asOf: Value(asOf),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
    );
  }

  factory FxRateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FxRateRow(
      id: serializer.fromJson<String>(json['id']),
      baseCurrency: serializer.fromJson<String>(json['baseCurrency']),
      quoteCurrency: serializer.fromJson<String>(json['quoteCurrency']),
      rate: serializer.fromJson<Decimal>(json['rate']),
      asOf: serializer.fromJson<DateTime>(json['asOf']),
      source: serializer.fromJson<String?>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'baseCurrency': serializer.toJson<String>(baseCurrency),
      'quoteCurrency': serializer.toJson<String>(quoteCurrency),
      'rate': serializer.toJson<Decimal>(rate),
      'asOf': serializer.toJson<DateTime>(asOf),
      'source': serializer.toJson<String?>(source),
    };
  }

  FxRateRow copyWith({
    String? id,
    String? baseCurrency,
    String? quoteCurrency,
    Decimal? rate,
    DateTime? asOf,
    Value<String?> source = const Value.absent(),
  }) => FxRateRow(
    id: id ?? this.id,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    quoteCurrency: quoteCurrency ?? this.quoteCurrency,
    rate: rate ?? this.rate,
    asOf: asOf ?? this.asOf,
    source: source.present ? source.value : this.source,
  );
  FxRateRow copyWithCompanion(FxRatesCompanion data) {
    return FxRateRow(
      id: data.id.present ? data.id.value : this.id,
      baseCurrency: data.baseCurrency.present
          ? data.baseCurrency.value
          : this.baseCurrency,
      quoteCurrency: data.quoteCurrency.present
          ? data.quoteCurrency.value
          : this.quoteCurrency,
      rate: data.rate.present ? data.rate.value : this.rate,
      asOf: data.asOf.present ? data.asOf.value : this.asOf,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FxRateRow(')
          ..write('id: $id, ')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('quoteCurrency: $quoteCurrency, ')
          ..write('rate: $rate, ')
          ..write('asOf: $asOf, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, baseCurrency, quoteCurrency, rate, asOf, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FxRateRow &&
          other.id == this.id &&
          other.baseCurrency == this.baseCurrency &&
          other.quoteCurrency == this.quoteCurrency &&
          other.rate == this.rate &&
          other.asOf == this.asOf &&
          other.source == this.source);
}

class FxRatesCompanion extends UpdateCompanion<FxRateRow> {
  final Value<String> id;
  final Value<String> baseCurrency;
  final Value<String> quoteCurrency;
  final Value<Decimal> rate;
  final Value<DateTime> asOf;
  final Value<String?> source;
  final Value<int> rowid;
  const FxRatesCompanion({
    this.id = const Value.absent(),
    this.baseCurrency = const Value.absent(),
    this.quoteCurrency = const Value.absent(),
    this.rate = const Value.absent(),
    this.asOf = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FxRatesCompanion.insert({
    required String id,
    required String baseCurrency,
    required String quoteCurrency,
    required Decimal rate,
    required DateTime asOf,
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       baseCurrency = Value(baseCurrency),
       quoteCurrency = Value(quoteCurrency),
       rate = Value(rate),
       asOf = Value(asOf);
  static Insertable<FxRateRow> custom({
    Expression<String>? id,
    Expression<String>? baseCurrency,
    Expression<String>? quoteCurrency,
    Expression<String>? rate,
    Expression<DateTime>? asOf,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (baseCurrency != null) 'base_currency': baseCurrency,
      if (quoteCurrency != null) 'quote_currency': quoteCurrency,
      if (rate != null) 'rate': rate,
      if (asOf != null) 'as_of': asOf,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FxRatesCompanion copyWith({
    Value<String>? id,
    Value<String>? baseCurrency,
    Value<String>? quoteCurrency,
    Value<Decimal>? rate,
    Value<DateTime>? asOf,
    Value<String?>? source,
    Value<int>? rowid,
  }) {
    return FxRatesCompanion(
      id: id ?? this.id,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      quoteCurrency: quoteCurrency ?? this.quoteCurrency,
      rate: rate ?? this.rate,
      asOf: asOf ?? this.asOf,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (baseCurrency.present) {
      map['base_currency'] = Variable<String>(baseCurrency.value);
    }
    if (quoteCurrency.present) {
      map['quote_currency'] = Variable<String>(quoteCurrency.value);
    }
    if (rate.present) {
      map['rate'] = Variable<String>(
        $FxRatesTable.$converterrate.toSql(rate.value),
      );
    }
    if (asOf.present) {
      map['as_of'] = Variable<DateTime>(asOf.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FxRatesCompanion(')
          ..write('id: $id, ')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('quoteCurrency: $quoteCurrency, ')
          ..write('rate: $rate, ')
          ..write('asOf: $asOf, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($TagsTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TagKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TagKind>($TagsTable.$converterkind);
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    kind,
    color,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $TagsTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: $TagsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<TagKind, String> $converterkind =
      const EnumStringConverter(TagKind.values);
}

class TagRow extends DataClass implements Insertable<TagRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String name;
  final TagKind kind;
  final String? color;
  const TagRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.name,
    required this.kind,
    this.color,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($TagsTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    {
      map['kind'] = Variable<String>($TagsTable.$converterkind.toSql(kind));
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
    );
  }

  factory TagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<TagKind>(json['kind']),
      color: serializer.fromJson<String?>(json['color']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<TagKind>(kind),
      'color': serializer.toJson<String?>(color),
    };
  }

  TagRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? name,
    TagKind? kind,
    Value<String?> color = const Value.absent(),
  }) => TagRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    color: color.present ? color.value : this.color,
  );
  TagRow copyWithCompanion(TagsCompanion data) {
    return TagRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      color: data.color.present ? data.color.value : this.color,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    kind,
    color,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.color == this.color);
}

class TagsCompanion extends UpdateCompanion<TagRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> name;
  final Value<TagKind> kind;
  final Value<String?> color;
  final Value<int> rowid;
  const TagsCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String name,
    required TagKind kind,
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       name = Value(name),
       kind = Value(kind);
  static Insertable<TagRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? color,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (color != null) 'color': color,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? name,
    Value<TagKind>? kind,
    Value<String?>? color,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      color: color ?? this.color,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>($TagsTable.$converterhlc.toSql(hlc.value));
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $TagsTable.$converterkind.toSql(kind.value),
      );
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('color: $color, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagLinksTable extends TagLinks
    with TableInfo<$TagLinksTable, TagLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($TagLinksTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTableMeta = const VerificationMeta(
    'entityTable',
  );
  @override
  late final GeneratedColumn<String> entityTable = GeneratedColumn<String>(
    'entity_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    tagId,
    entityTable,
    entityId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tag_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('entity_table')) {
      context.handle(
        _entityTableMeta,
        entityTable.isAcceptableOrUnknown(
          data['entity_table']!,
          _entityTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityTableMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagLinkRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $TagLinksTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      entityTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_table'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
    );
  }

  @override
  $TagLinksTable createAlias(String alias) {
    return $TagLinksTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
}

class TagLinkRow extends DataClass implements Insertable<TagLinkRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String tagId;
  final String entityTable;
  final String entityId;
  const TagLinkRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.tagId,
    required this.entityTable,
    required this.entityId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($TagLinksTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['tag_id'] = Variable<String>(tagId);
    map['entity_table'] = Variable<String>(entityTable);
    map['entity_id'] = Variable<String>(entityId);
    return map;
  }

  TagLinksCompanion toCompanion(bool nullToAbsent) {
    return TagLinksCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      tagId: Value(tagId),
      entityTable: Value(entityTable),
      entityId: Value(entityId),
    );
  }

  factory TagLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagLinkRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      tagId: serializer.fromJson<String>(json['tagId']),
      entityTable: serializer.fromJson<String>(json['entityTable']),
      entityId: serializer.fromJson<String>(json['entityId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'tagId': serializer.toJson<String>(tagId),
      'entityTable': serializer.toJson<String>(entityTable),
      'entityId': serializer.toJson<String>(entityId),
    };
  }

  TagLinkRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? tagId,
    String? entityTable,
    String? entityId,
  }) => TagLinkRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    tagId: tagId ?? this.tagId,
    entityTable: entityTable ?? this.entityTable,
    entityId: entityId ?? this.entityId,
  );
  TagLinkRow copyWithCompanion(TagLinksCompanion data) {
    return TagLinkRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      entityTable: data.entityTable.present
          ? data.entityTable.value
          : this.entityTable,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagLinkRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('tagId: $tagId, ')
          ..write('entityTable: $entityTable, ')
          ..write('entityId: $entityId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    tagId,
    entityTable,
    entityId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagLinkRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.tagId == this.tagId &&
          other.entityTable == this.entityTable &&
          other.entityId == this.entityId);
}

class TagLinksCompanion extends UpdateCompanion<TagLinkRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> tagId;
  final Value<String> entityTable;
  final Value<String> entityId;
  final Value<int> rowid;
  const TagLinksCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.tagId = const Value.absent(),
    this.entityTable = const Value.absent(),
    this.entityId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagLinksCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String tagId,
    required String entityTable,
    required String entityId,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       tagId = Value(tagId),
       entityTable = Value(entityTable),
       entityId = Value(entityId);
  static Insertable<TagLinkRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? tagId,
    Expression<String>? entityTable,
    Expression<String>? entityId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (tagId != null) 'tag_id': tagId,
      if (entityTable != null) 'entity_table': entityTable,
      if (entityId != null) 'entity_id': entityId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagLinksCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? tagId,
    Value<String>? entityTable,
    Value<String>? entityId,
    Value<int>? rowid,
  }) {
    return TagLinksCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      tagId: tagId ?? this.tagId,
      entityTable: entityTable ?? this.entityTable,
      entityId: entityId ?? this.entityId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $TagLinksTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (entityTable.present) {
      map['entity_table'] = Variable<String>(entityTable.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagLinksCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('tagId: $tagId, ')
          ..write('entityTable: $entityTable, ')
          ..write('entityId: $entityId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($CategoriesTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    parentId,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $CategoriesTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      ),
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String name;
  final String? parentId;
  final int? sortOrder;
  const CategoryRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($CategoriesTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || sortOrder != null) {
      map['sort_order'] = Variable<int>(sortOrder);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      name: Value(name),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      sortOrder: sortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(sortOrder),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      sortOrder: serializer.fromJson<int?>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'parentId': serializer.toJson<String?>(parentId),
      'sortOrder': serializer.toJson<int?>(sortOrder),
    };
  }

  CategoryRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? name,
    Value<String?> parentId = const Value.absent(),
    Value<int?> sortOrder = const Value.absent(),
  }) => CategoryRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    name: name ?? this.name,
    parentId: parentId.present ? parentId.value : this.parentId,
    sortOrder: sortOrder.present ? sortOrder.value : this.sortOrder,
  );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    parentId,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.name == this.name &&
          other.parentId == this.parentId &&
          other.sortOrder == this.sortOrder);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> parentId;
  final Value<int?> sortOrder;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.parentId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String name,
    this.parentId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       name = Value(name);
  static Insertable<CategoryRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? parentId,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? parentId,
    Value<int?>? sortOrder,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $CategoriesTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpenseCategoriesTable extends ExpenseCategories
    with TableInfo<$ExpenseCategoriesTable, ExpenseCategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpenseCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($ExpenseCategoriesTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    parentId,
    icon,
    color,
    sortOrder,
    archivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expense_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseCategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExpenseCategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseCategoryRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $ExpenseCategoriesTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      ),
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
    );
  }

  @override
  $ExpenseCategoriesTable createAlias(String alias) {
    return $ExpenseCategoriesTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
}

class ExpenseCategoryRow extends DataClass
    implements Insertable<ExpenseCategoryRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String name;
  final String? parentId;
  final String? icon;
  final String? color;
  final int? sortOrder;
  final DateTime? archivedAt;
  const ExpenseCategoryRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.name,
    this.parentId,
    this.icon,
    this.color,
    this.sortOrder,
    this.archivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>(
        $ExpenseCategoriesTable.$converterhlc.toSql(hlc),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    if (!nullToAbsent || sortOrder != null) {
      map['sort_order'] = Variable<int>(sortOrder);
    }
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    return map;
  }

  ExpenseCategoriesCompanion toCompanion(bool nullToAbsent) {
    return ExpenseCategoriesCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      name: Value(name),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      sortOrder: sortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
    );
  }

  factory ExpenseCategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseCategoryRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      icon: serializer.fromJson<String?>(json['icon']),
      color: serializer.fromJson<String?>(json['color']),
      sortOrder: serializer.fromJson<int?>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'parentId': serializer.toJson<String?>(parentId),
      'icon': serializer.toJson<String?>(icon),
      'color': serializer.toJson<String?>(color),
      'sortOrder': serializer.toJson<int?>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
    };
  }

  ExpenseCategoryRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? name,
    Value<String?> parentId = const Value.absent(),
    Value<String?> icon = const Value.absent(),
    Value<String?> color = const Value.absent(),
    Value<int?> sortOrder = const Value.absent(),
    Value<DateTime?> archivedAt = const Value.absent(),
  }) => ExpenseCategoryRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    name: name ?? this.name,
    parentId: parentId.present ? parentId.value : this.parentId,
    icon: icon.present ? icon.value : this.icon,
    color: color.present ? color.value : this.color,
    sortOrder: sortOrder.present ? sortOrder.value : this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
  );
  ExpenseCategoryRow copyWithCompanion(ExpenseCategoriesCompanion data) {
    return ExpenseCategoryRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseCategoryRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    parentId,
    icon,
    color,
    sortOrder,
    archivedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseCategoryRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.name == this.name &&
          other.parentId == this.parentId &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt);
}

class ExpenseCategoriesCompanion extends UpdateCompanion<ExpenseCategoryRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> parentId;
  final Value<String?> icon;
  final Value<String?> color;
  final Value<int?> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<int> rowid;
  const ExpenseCategoriesCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.parentId = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpenseCategoriesCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String name,
    this.parentId = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       name = Value(name);
  static Insertable<ExpenseCategoryRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? parentId,
    Expression<String>? icon,
    Expression<String>? color,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpenseCategoriesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? parentId,
    Value<String?>? icon,
    Value<String?>? color,
    Value<int?>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<int>? rowid,
  }) {
    return ExpenseCategoriesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $ExpenseCategoriesTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseCategoriesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoalsTable extends Goals with TableInfo<$GoalsTable, GoalRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($GoalsTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<GoalType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<GoalType>($GoalsTable.$convertertype);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal?, String> targetAmount =
      GeneratedColumn<String>(
        'target_amount',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Decimal?>($GoalsTable.$convertertargetAmountn);
  static const VerificationMeta _targetDateMeta = const VerificationMeta(
    'targetDate',
  );
  @override
  late final GeneratedColumn<DateTime> targetDate = GeneratedColumn<DateTime>(
    'target_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetAllocationJsonMeta =
      const VerificationMeta('targetAllocationJson');
  @override
  late final GeneratedColumn<String> targetAllocationJson =
      GeneratedColumn<String>(
        'target_allocation_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    type,
    name,
    currency,
    targetAmount,
    targetDate,
    targetAllocationJson,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goals';
  @override
  VerificationContext validateIntegrity(
    Insertable<GoalRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    }
    if (data.containsKey('target_date')) {
      context.handle(
        _targetDateMeta,
        targetDate.isAcceptableOrUnknown(data['target_date']!, _targetDateMeta),
      );
    }
    if (data.containsKey('target_allocation_json')) {
      context.handle(
        _targetAllocationJsonMeta,
        targetAllocationJson.isAcceptableOrUnknown(
          data['target_allocation_json']!,
          _targetAllocationJsonMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GoalRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GoalRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $GoalsTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: $GoalsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      ),
      targetAmount: $GoalsTable.$convertertargetAmountn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}target_amount'],
        ),
      ),
      targetDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}target_date'],
      ),
      targetAllocationJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_allocation_json'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $GoalsTable createAlias(String alias) {
    return $GoalsTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<GoalType, String> $convertertype =
      const EnumStringConverter(GoalType.values);
  static TypeConverter<Decimal, String> $convertertargetAmount =
      const DecimalConverter();
  static TypeConverter<Decimal?, String?> $convertertargetAmountn =
      NullAwareTypeConverter.wrap($convertertargetAmount);
}

class GoalRow extends DataClass implements Insertable<GoalRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final GoalType type;
  final String name;
  final String? currency;
  final Decimal? targetAmount;
  final DateTime? targetDate;
  final String? targetAllocationJson;
  final String? note;
  const GoalRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.type,
    required this.name,
    this.currency,
    this.targetAmount,
    this.targetDate,
    this.targetAllocationJson,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($GoalsTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    {
      map['type'] = Variable<String>($GoalsTable.$convertertype.toSql(type));
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || currency != null) {
      map['currency'] = Variable<String>(currency);
    }
    if (!nullToAbsent || targetAmount != null) {
      map['target_amount'] = Variable<String>(
        $GoalsTable.$convertertargetAmountn.toSql(targetAmount),
      );
    }
    if (!nullToAbsent || targetDate != null) {
      map['target_date'] = Variable<DateTime>(targetDate);
    }
    if (!nullToAbsent || targetAllocationJson != null) {
      map['target_allocation_json'] = Variable<String>(targetAllocationJson);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  GoalsCompanion toCompanion(bool nullToAbsent) {
    return GoalsCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      type: Value(type),
      name: Value(name),
      currency: currency == null && nullToAbsent
          ? const Value.absent()
          : Value(currency),
      targetAmount: targetAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(targetAmount),
      targetDate: targetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDate),
      targetAllocationJson: targetAllocationJson == null && nullToAbsent
          ? const Value.absent()
          : Value(targetAllocationJson),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory GoalRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GoalRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<GoalType>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      currency: serializer.fromJson<String?>(json['currency']),
      targetAmount: serializer.fromJson<Decimal?>(json['targetAmount']),
      targetDate: serializer.fromJson<DateTime?>(json['targetDate']),
      targetAllocationJson: serializer.fromJson<String?>(
        json['targetAllocationJson'],
      ),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<GoalType>(type),
      'name': serializer.toJson<String>(name),
      'currency': serializer.toJson<String?>(currency),
      'targetAmount': serializer.toJson<Decimal?>(targetAmount),
      'targetDate': serializer.toJson<DateTime?>(targetDate),
      'targetAllocationJson': serializer.toJson<String?>(targetAllocationJson),
      'note': serializer.toJson<String?>(note),
    };
  }

  GoalRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    GoalType? type,
    String? name,
    Value<String?> currency = const Value.absent(),
    Value<Decimal?> targetAmount = const Value.absent(),
    Value<DateTime?> targetDate = const Value.absent(),
    Value<String?> targetAllocationJson = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) => GoalRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    type: type ?? this.type,
    name: name ?? this.name,
    currency: currency.present ? currency.value : this.currency,
    targetAmount: targetAmount.present ? targetAmount.value : this.targetAmount,
    targetDate: targetDate.present ? targetDate.value : this.targetDate,
    targetAllocationJson: targetAllocationJson.present
        ? targetAllocationJson.value
        : this.targetAllocationJson,
    note: note.present ? note.value : this.note,
  );
  GoalRow copyWithCompanion(GoalsCompanion data) {
    return GoalRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      currency: data.currency.present ? data.currency.value : this.currency,
      targetAmount: data.targetAmount.present
          ? data.targetAmount.value
          : this.targetAmount,
      targetDate: data.targetDate.present
          ? data.targetDate.value
          : this.targetDate,
      targetAllocationJson: data.targetAllocationJson.present
          ? data.targetAllocationJson.value
          : this.targetAllocationJson,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GoalRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('targetAmount: $targetAmount, ')
          ..write('targetDate: $targetDate, ')
          ..write('targetAllocationJson: $targetAllocationJson, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    type,
    name,
    currency,
    targetAmount,
    targetDate,
    targetAllocationJson,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoalRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.type == this.type &&
          other.name == this.name &&
          other.currency == this.currency &&
          other.targetAmount == this.targetAmount &&
          other.targetDate == this.targetDate &&
          other.targetAllocationJson == this.targetAllocationJson &&
          other.note == this.note);
}

class GoalsCompanion extends UpdateCompanion<GoalRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<GoalType> type;
  final Value<String> name;
  final Value<String?> currency;
  final Value<Decimal?> targetAmount;
  final Value<DateTime?> targetDate;
  final Value<String?> targetAllocationJson;
  final Value<String?> note;
  final Value<int> rowid;
  const GoalsCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.currency = const Value.absent(),
    this.targetAmount = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.targetAllocationJson = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoalsCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required GoalType type,
    required String name,
    this.currency = const Value.absent(),
    this.targetAmount = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.targetAllocationJson = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       type = Value(type),
       name = Value(name);
  static Insertable<GoalRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? currency,
    Expression<String>? targetAmount,
    Expression<DateTime>? targetDate,
    Expression<String>? targetAllocationJson,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (currency != null) 'currency': currency,
      if (targetAmount != null) 'target_amount': targetAmount,
      if (targetDate != null) 'target_date': targetDate,
      if (targetAllocationJson != null)
        'target_allocation_json': targetAllocationJson,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoalsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<GoalType>? type,
    Value<String>? name,
    Value<String?>? currency,
    Value<Decimal?>? targetAmount,
    Value<DateTime?>? targetDate,
    Value<String?>? targetAllocationJson,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return GoalsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      targetAmount: targetAmount ?? this.targetAmount,
      targetDate: targetDate ?? this.targetDate,
      targetAllocationJson: targetAllocationJson ?? this.targetAllocationJson,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>($GoalsTable.$converterhlc.toSql(hlc.value));
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $GoalsTable.$convertertype.toSql(type.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (targetAmount.present) {
      map['target_amount'] = Variable<String>(
        $GoalsTable.$convertertargetAmountn.toSql(targetAmount.value),
      );
    }
    if (targetDate.present) {
      map['target_date'] = Variable<DateTime>(targetDate.value);
    }
    if (targetAllocationJson.present) {
      map['target_allocation_json'] = Variable<String>(
        targetAllocationJson.value,
      );
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoalsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('targetAmount: $targetAmount, ')
          ..write('targetDate: $targetDate, ')
          ..write('targetAllocationJson: $targetAllocationJson, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DevicesTable extends Devices with TableInfo<$DevicesTable, DeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($DevicesTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DevicePlatform, String> platform =
      GeneratedColumn<String>(
        'platform',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DevicePlatform>($DevicesTable.$converterplatform);
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc?, String> lastHlc =
      GeneratedColumn<String>(
        'last_hlc',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Hlc?>($DevicesTable.$converterlastHlcn);
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    platform,
    appVersion,
    lastSyncAt,
    lastHlc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $DevicesTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      platform: $DevicesTable.$converterplatform.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}platform'],
        )!,
      ),
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      ),
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
      lastHlc: $DevicesTable.$converterlastHlcn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_hlc'],
        ),
      ),
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<DevicePlatform, String> $converterplatform =
      const EnumStringConverter(DevicePlatform.values);
  static TypeConverter<Hlc, String> $converterlastHlc = const HlcConverter();
  static TypeConverter<Hlc?, String?> $converterlastHlcn =
      NullAwareTypeConverter.wrap($converterlastHlc);
}

class DeviceRow extends DataClass implements Insertable<DeviceRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String name;
  final DevicePlatform platform;
  final String? appVersion;
  final DateTime? lastSyncAt;
  final Hlc? lastHlc;
  const DeviceRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.name,
    required this.platform,
    this.appVersion,
    this.lastSyncAt,
    this.lastHlc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($DevicesTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    {
      map['platform'] = Variable<String>(
        $DevicesTable.$converterplatform.toSql(platform),
      );
    }
    if (!nullToAbsent || appVersion != null) {
      map['app_version'] = Variable<String>(appVersion);
    }
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    if (!nullToAbsent || lastHlc != null) {
      map['last_hlc'] = Variable<String>(
        $DevicesTable.$converterlastHlcn.toSql(lastHlc),
      );
    }
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      name: Value(name),
      platform: Value(platform),
      appVersion: appVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(appVersion),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      lastHlc: lastHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastHlc),
    );
  }

  factory DeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      platform: serializer.fromJson<DevicePlatform>(json['platform']),
      appVersion: serializer.fromJson<String?>(json['appVersion']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
      lastHlc: serializer.fromJson<Hlc?>(json['lastHlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'platform': serializer.toJson<DevicePlatform>(platform),
      'appVersion': serializer.toJson<String?>(appVersion),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
      'lastHlc': serializer.toJson<Hlc?>(lastHlc),
    };
  }

  DeviceRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? name,
    DevicePlatform? platform,
    Value<String?> appVersion = const Value.absent(),
    Value<DateTime?> lastSyncAt = const Value.absent(),
    Value<Hlc?> lastHlc = const Value.absent(),
  }) => DeviceRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    appVersion: appVersion.present ? appVersion.value : this.appVersion,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    lastHlc: lastHlc.present ? lastHlc.value : this.lastHlc,
  );
  DeviceRow copyWithCompanion(DevicesCompanion data) {
    return DeviceRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      platform: data.platform.present ? data.platform.value : this.platform,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      lastHlc: data.lastHlc.present ? data.lastHlc.value : this.lastHlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('appVersion: $appVersion, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastHlc: $lastHlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    name,
    platform,
    appVersion,
    lastSyncAt,
    lastHlc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.name == this.name &&
          other.platform == this.platform &&
          other.appVersion == this.appVersion &&
          other.lastSyncAt == this.lastSyncAt &&
          other.lastHlc == this.lastHlc);
}

class DevicesCompanion extends UpdateCompanion<DeviceRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> name;
  final Value<DevicePlatform> platform;
  final Value<String?> appVersion;
  final Value<DateTime?> lastSyncAt;
  final Value<Hlc?> lastHlc;
  final Value<int> rowid;
  const DevicesCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String name,
    required DevicePlatform platform,
    this.appVersion = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       name = Value(name),
       platform = Value(platform);
  static Insertable<DeviceRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? platform,
    Expression<String>? appVersion,
    Expression<DateTime>? lastSyncAt,
    Expression<String>? lastHlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'app_version': appVersion,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (lastHlc != null) 'last_hlc': lastHlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? name,
    Value<DevicePlatform>? platform,
    Value<String?>? appVersion,
    Value<DateTime?>? lastSyncAt,
    Value<Hlc?>? lastHlc,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastHlc: lastHlc ?? this.lastHlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $DevicesTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(
        $DevicesTable.$converterplatform.toSql(platform.value),
      );
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (lastHlc.present) {
      map['last_hlc'] = Variable<String>(
        $DevicesTable.$converterlastHlcn.toSql(lastHlc.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('appVersion: $appVersion, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastHlc: $lastHlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OpLogsTable extends OpLogs with TableInfo<$OpLogsTable, OpLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OpLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($OpLogsTable.$converterhlc);
  @override
  late final GeneratedColumnWithTypeConverter<OpKind, String> op =
      GeneratedColumn<String>(
        'op',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<OpKind>($OpLogsTable.$converterop);
  static const VerificationMeta _entityTableMeta = const VerificationMeta(
    'entityTable',
  );
  @override
  late final GeneratedColumn<String> entityTable = GeneratedColumn<String>(
    'entity_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patchJsonMeta = const VerificationMeta(
    'patchJson',
  );
  @override
  late final GeneratedColumn<String> patchJson = GeneratedColumn<String>(
    'patch_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerUserId,
    deviceId,
    hlc,
    op,
    entityTable,
    entityId,
    patchJson,
    syncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'op_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<OpLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('entity_table')) {
      context.handle(
        _entityTableMeta,
        entityTable.isAcceptableOrUnknown(
          data['entity_table']!,
          _entityTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityTableMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('patch_json')) {
      context.handle(
        _patchJsonMeta,
        patchJson.isAcceptableOrUnknown(data['patch_json']!, _patchJsonMeta),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OpLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OpLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      hlc: $OpLogsTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      op: $OpLogsTable.$converterop.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}op'],
        )!,
      ),
      entityTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_table'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      patchJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patch_json'],
      ),
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
    );
  }

  @override
  $OpLogsTable createAlias(String alias) {
    return $OpLogsTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<OpKind, String> $converterop = const EnumStringConverter(
    OpKind.values,
  );
}

class OpLogRow extends DataClass implements Insertable<OpLogRow> {
  final String id;
  final String ownerUserId;
  final String deviceId;
  final Hlc hlc;
  final OpKind op;
  final String entityTable;
  final String entityId;
  final String? patchJson;
  final DateTime? syncedAt;
  const OpLogRow({
    required this.id,
    required this.ownerUserId,
    required this.deviceId,
    required this.hlc,
    required this.op,
    required this.entityTable,
    required this.entityId,
    this.patchJson,
    this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['device_id'] = Variable<String>(deviceId);
    {
      map['hlc'] = Variable<String>($OpLogsTable.$converterhlc.toSql(hlc));
    }
    {
      map['op'] = Variable<String>($OpLogsTable.$converterop.toSql(op));
    }
    map['entity_table'] = Variable<String>(entityTable);
    map['entity_id'] = Variable<String>(entityId);
    if (!nullToAbsent || patchJson != null) {
      map['patch_json'] = Variable<String>(patchJson);
    }
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  OpLogsCompanion toCompanion(bool nullToAbsent) {
    return OpLogsCompanion(
      id: Value(id),
      ownerUserId: Value(ownerUserId),
      deviceId: Value(deviceId),
      hlc: Value(hlc),
      op: Value(op),
      entityTable: Value(entityTable),
      entityId: Value(entityId),
      patchJson: patchJson == null && nullToAbsent
          ? const Value.absent()
          : Value(patchJson),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory OpLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OpLogRow(
      id: serializer.fromJson<String>(json['id']),
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      op: serializer.fromJson<OpKind>(json['op']),
      entityTable: serializer.fromJson<String>(json['entityTable']),
      entityId: serializer.fromJson<String>(json['entityId']),
      patchJson: serializer.fromJson<String?>(json['patchJson']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'deviceId': serializer.toJson<String>(deviceId),
      'hlc': serializer.toJson<Hlc>(hlc),
      'op': serializer.toJson<OpKind>(op),
      'entityTable': serializer.toJson<String>(entityTable),
      'entityId': serializer.toJson<String>(entityId),
      'patchJson': serializer.toJson<String?>(patchJson),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  OpLogRow copyWith({
    String? id,
    String? ownerUserId,
    String? deviceId,
    Hlc? hlc,
    OpKind? op,
    String? entityTable,
    String? entityId,
    Value<String?> patchJson = const Value.absent(),
    Value<DateTime?> syncedAt = const Value.absent(),
  }) => OpLogRow(
    id: id ?? this.id,
    ownerUserId: ownerUserId ?? this.ownerUserId,
    deviceId: deviceId ?? this.deviceId,
    hlc: hlc ?? this.hlc,
    op: op ?? this.op,
    entityTable: entityTable ?? this.entityTable,
    entityId: entityId ?? this.entityId,
    patchJson: patchJson.present ? patchJson.value : this.patchJson,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
  );
  OpLogRow copyWithCompanion(OpLogsCompanion data) {
    return OpLogRow(
      id: data.id.present ? data.id.value : this.id,
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      op: data.op.present ? data.op.value : this.op,
      entityTable: data.entityTable.present
          ? data.entityTable.value
          : this.entityTable,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      patchJson: data.patchJson.present ? data.patchJson.value : this.patchJson,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OpLogRow(')
          ..write('id: $id, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('deviceId: $deviceId, ')
          ..write('hlc: $hlc, ')
          ..write('op: $op, ')
          ..write('entityTable: $entityTable, ')
          ..write('entityId: $entityId, ')
          ..write('patchJson: $patchJson, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerUserId,
    deviceId,
    hlc,
    op,
    entityTable,
    entityId,
    patchJson,
    syncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OpLogRow &&
          other.id == this.id &&
          other.ownerUserId == this.ownerUserId &&
          other.deviceId == this.deviceId &&
          other.hlc == this.hlc &&
          other.op == this.op &&
          other.entityTable == this.entityTable &&
          other.entityId == this.entityId &&
          other.patchJson == this.patchJson &&
          other.syncedAt == this.syncedAt);
}

class OpLogsCompanion extends UpdateCompanion<OpLogRow> {
  final Value<String> id;
  final Value<String> ownerUserId;
  final Value<String> deviceId;
  final Value<Hlc> hlc;
  final Value<OpKind> op;
  final Value<String> entityTable;
  final Value<String> entityId;
  final Value<String?> patchJson;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const OpLogsCompanion({
    this.id = const Value.absent(),
    this.ownerUserId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.hlc = const Value.absent(),
    this.op = const Value.absent(),
    this.entityTable = const Value.absent(),
    this.entityId = const Value.absent(),
    this.patchJson = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OpLogsCompanion.insert({
    required String id,
    required String ownerUserId,
    required String deviceId,
    required Hlc hlc,
    required OpKind op,
    required String entityTable,
    required String entityId,
    this.patchJson = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerUserId = Value(ownerUserId),
       deviceId = Value(deviceId),
       hlc = Value(hlc),
       op = Value(op),
       entityTable = Value(entityTable),
       entityId = Value(entityId);
  static Insertable<OpLogRow> custom({
    Expression<String>? id,
    Expression<String>? ownerUserId,
    Expression<String>? deviceId,
    Expression<String>? hlc,
    Expression<String>? op,
    Expression<String>? entityTable,
    Expression<String>? entityId,
    Expression<String>? patchJson,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (deviceId != null) 'device_id': deviceId,
      if (hlc != null) 'hlc': hlc,
      if (op != null) 'op': op,
      if (entityTable != null) 'entity_table': entityTable,
      if (entityId != null) 'entity_id': entityId,
      if (patchJson != null) 'patch_json': patchJson,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OpLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerUserId,
    Value<String>? deviceId,
    Value<Hlc>? hlc,
    Value<OpKind>? op,
    Value<String>? entityTable,
    Value<String>? entityId,
    Value<String?>? patchJson,
    Value<DateTime?>? syncedAt,
    Value<int>? rowid,
  }) {
    return OpLogsCompanion(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      deviceId: deviceId ?? this.deviceId,
      hlc: hlc ?? this.hlc,
      op: op ?? this.op,
      entityTable: entityTable ?? this.entityTable,
      entityId: entityId ?? this.entityId,
      patchJson: patchJson ?? this.patchJson,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $OpLogsTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (op.present) {
      map['op'] = Variable<String>($OpLogsTable.$converterop.toSql(op.value));
    }
    if (entityTable.present) {
      map['entity_table'] = Variable<String>(entityTable.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (patchJson.present) {
      map['patch_json'] = Variable<String>(patchJson.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OpLogsCompanion(')
          ..write('id: $id, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('deviceId: $deviceId, ')
          ..write('hlc: $hlc, ')
          ..write('op: $op, ')
          ..write('entityTable: $entityTable, ')
          ..write('entityId: $entityId, ')
          ..write('patchJson: $patchJson, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MarketQuotesTable extends MarketQuotes
    with TableInfo<$MarketQuotesTable, MarketQuoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MarketQuotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<String> price = GeneratedColumn<String>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previousCloseMeta = const VerificationMeta(
    'previousClose',
  );
  @override
  late final GeneratedColumn<String> previousClose = GeneratedColumn<String>(
    'previous_close',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _openPriceMeta = const VerificationMeta(
    'openPrice',
  );
  @override
  late final GeneratedColumn<String> openPrice = GeneratedColumn<String>(
    'open_price',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayHighMeta = const VerificationMeta(
    'dayHigh',
  );
  @override
  late final GeneratedColumn<String> dayHigh = GeneratedColumn<String>(
    'day_high',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayLowMeta = const VerificationMeta('dayLow');
  @override
  late final GeneratedColumn<String> dayLow = GeneratedColumn<String>(
    'day_low',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<int> volume = GeneratedColumn<int>(
    'volume',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exchangeMeta = const VerificationMeta(
    'exchange',
  );
  @override
  late final GeneratedColumn<String> exchange = GeneratedColumn<String>(
    'exchange',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _asOfMeta = const VerificationMeta('asOf');
  @override
  late final GeneratedColumn<DateTime> asOf = GeneratedColumn<DateTime>(
    'as_of',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    symbol,
    source,
    currency,
    price,
    previousClose,
    openPrice,
    dayHigh,
    dayLow,
    volume,
    exchange,
    asOf,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'market_quotes';
  @override
  VerificationContext validateIntegrity(
    Insertable<MarketQuoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('previous_close')) {
      context.handle(
        _previousCloseMeta,
        previousClose.isAcceptableOrUnknown(
          data['previous_close']!,
          _previousCloseMeta,
        ),
      );
    }
    if (data.containsKey('open_price')) {
      context.handle(
        _openPriceMeta,
        openPrice.isAcceptableOrUnknown(data['open_price']!, _openPriceMeta),
      );
    }
    if (data.containsKey('day_high')) {
      context.handle(
        _dayHighMeta,
        dayHigh.isAcceptableOrUnknown(data['day_high']!, _dayHighMeta),
      );
    }
    if (data.containsKey('day_low')) {
      context.handle(
        _dayLowMeta,
        dayLow.isAcceptableOrUnknown(data['day_low']!, _dayLowMeta),
      );
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    }
    if (data.containsKey('exchange')) {
      context.handle(
        _exchangeMeta,
        exchange.isAcceptableOrUnknown(data['exchange']!, _exchangeMeta),
      );
    }
    if (data.containsKey('as_of')) {
      context.handle(
        _asOfMeta,
        asOf.isAcceptableOrUnknown(data['as_of']!, _asOfMeta),
      );
    } else if (isInserting) {
      context.missing(_asOfMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {symbol, source};
  @override
  MarketQuoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MarketQuoteRow(
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}price'],
      )!,
      previousClose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_close'],
      ),
      openPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}open_price'],
      ),
      dayHigh: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_high'],
      ),
      dayLow: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_low'],
      ),
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}volume'],
      ),
      exchange: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exchange'],
      ),
      asOf: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}as_of'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $MarketQuotesTable createAlias(String alias) {
    return $MarketQuotesTable(attachedDatabase, alias);
  }
}

class MarketQuoteRow extends DataClass implements Insertable<MarketQuoteRow> {
  final String symbol;
  final String source;
  final String currency;
  final String price;
  final String? previousClose;
  final String? openPrice;
  final String? dayHigh;
  final String? dayLow;
  final int? volume;
  final String? exchange;
  final DateTime asOf;
  final DateTime fetchedAt;
  const MarketQuoteRow({
    required this.symbol,
    required this.source,
    required this.currency,
    required this.price,
    this.previousClose,
    this.openPrice,
    this.dayHigh,
    this.dayLow,
    this.volume,
    this.exchange,
    required this.asOf,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['symbol'] = Variable<String>(symbol);
    map['source'] = Variable<String>(source);
    map['currency'] = Variable<String>(currency);
    map['price'] = Variable<String>(price);
    if (!nullToAbsent || previousClose != null) {
      map['previous_close'] = Variable<String>(previousClose);
    }
    if (!nullToAbsent || openPrice != null) {
      map['open_price'] = Variable<String>(openPrice);
    }
    if (!nullToAbsent || dayHigh != null) {
      map['day_high'] = Variable<String>(dayHigh);
    }
    if (!nullToAbsent || dayLow != null) {
      map['day_low'] = Variable<String>(dayLow);
    }
    if (!nullToAbsent || volume != null) {
      map['volume'] = Variable<int>(volume);
    }
    if (!nullToAbsent || exchange != null) {
      map['exchange'] = Variable<String>(exchange);
    }
    map['as_of'] = Variable<DateTime>(asOf);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  MarketQuotesCompanion toCompanion(bool nullToAbsent) {
    return MarketQuotesCompanion(
      symbol: Value(symbol),
      source: Value(source),
      currency: Value(currency),
      price: Value(price),
      previousClose: previousClose == null && nullToAbsent
          ? const Value.absent()
          : Value(previousClose),
      openPrice: openPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(openPrice),
      dayHigh: dayHigh == null && nullToAbsent
          ? const Value.absent()
          : Value(dayHigh),
      dayLow: dayLow == null && nullToAbsent
          ? const Value.absent()
          : Value(dayLow),
      volume: volume == null && nullToAbsent
          ? const Value.absent()
          : Value(volume),
      exchange: exchange == null && nullToAbsent
          ? const Value.absent()
          : Value(exchange),
      asOf: Value(asOf),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory MarketQuoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MarketQuoteRow(
      symbol: serializer.fromJson<String>(json['symbol']),
      source: serializer.fromJson<String>(json['source']),
      currency: serializer.fromJson<String>(json['currency']),
      price: serializer.fromJson<String>(json['price']),
      previousClose: serializer.fromJson<String?>(json['previousClose']),
      openPrice: serializer.fromJson<String?>(json['openPrice']),
      dayHigh: serializer.fromJson<String?>(json['dayHigh']),
      dayLow: serializer.fromJson<String?>(json['dayLow']),
      volume: serializer.fromJson<int?>(json['volume']),
      exchange: serializer.fromJson<String?>(json['exchange']),
      asOf: serializer.fromJson<DateTime>(json['asOf']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'source': serializer.toJson<String>(source),
      'currency': serializer.toJson<String>(currency),
      'price': serializer.toJson<String>(price),
      'previousClose': serializer.toJson<String?>(previousClose),
      'openPrice': serializer.toJson<String?>(openPrice),
      'dayHigh': serializer.toJson<String?>(dayHigh),
      'dayLow': serializer.toJson<String?>(dayLow),
      'volume': serializer.toJson<int?>(volume),
      'exchange': serializer.toJson<String?>(exchange),
      'asOf': serializer.toJson<DateTime>(asOf),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  MarketQuoteRow copyWith({
    String? symbol,
    String? source,
    String? currency,
    String? price,
    Value<String?> previousClose = const Value.absent(),
    Value<String?> openPrice = const Value.absent(),
    Value<String?> dayHigh = const Value.absent(),
    Value<String?> dayLow = const Value.absent(),
    Value<int?> volume = const Value.absent(),
    Value<String?> exchange = const Value.absent(),
    DateTime? asOf,
    DateTime? fetchedAt,
  }) => MarketQuoteRow(
    symbol: symbol ?? this.symbol,
    source: source ?? this.source,
    currency: currency ?? this.currency,
    price: price ?? this.price,
    previousClose: previousClose.present
        ? previousClose.value
        : this.previousClose,
    openPrice: openPrice.present ? openPrice.value : this.openPrice,
    dayHigh: dayHigh.present ? dayHigh.value : this.dayHigh,
    dayLow: dayLow.present ? dayLow.value : this.dayLow,
    volume: volume.present ? volume.value : this.volume,
    exchange: exchange.present ? exchange.value : this.exchange,
    asOf: asOf ?? this.asOf,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  MarketQuoteRow copyWithCompanion(MarketQuotesCompanion data) {
    return MarketQuoteRow(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      source: data.source.present ? data.source.value : this.source,
      currency: data.currency.present ? data.currency.value : this.currency,
      price: data.price.present ? data.price.value : this.price,
      previousClose: data.previousClose.present
          ? data.previousClose.value
          : this.previousClose,
      openPrice: data.openPrice.present ? data.openPrice.value : this.openPrice,
      dayHigh: data.dayHigh.present ? data.dayHigh.value : this.dayHigh,
      dayLow: data.dayLow.present ? data.dayLow.value : this.dayLow,
      volume: data.volume.present ? data.volume.value : this.volume,
      exchange: data.exchange.present ? data.exchange.value : this.exchange,
      asOf: data.asOf.present ? data.asOf.value : this.asOf,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MarketQuoteRow(')
          ..write('symbol: $symbol, ')
          ..write('source: $source, ')
          ..write('currency: $currency, ')
          ..write('price: $price, ')
          ..write('previousClose: $previousClose, ')
          ..write('openPrice: $openPrice, ')
          ..write('dayHigh: $dayHigh, ')
          ..write('dayLow: $dayLow, ')
          ..write('volume: $volume, ')
          ..write('exchange: $exchange, ')
          ..write('asOf: $asOf, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    source,
    currency,
    price,
    previousClose,
    openPrice,
    dayHigh,
    dayLow,
    volume,
    exchange,
    asOf,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MarketQuoteRow &&
          other.symbol == this.symbol &&
          other.source == this.source &&
          other.currency == this.currency &&
          other.price == this.price &&
          other.previousClose == this.previousClose &&
          other.openPrice == this.openPrice &&
          other.dayHigh == this.dayHigh &&
          other.dayLow == this.dayLow &&
          other.volume == this.volume &&
          other.exchange == this.exchange &&
          other.asOf == this.asOf &&
          other.fetchedAt == this.fetchedAt);
}

class MarketQuotesCompanion extends UpdateCompanion<MarketQuoteRow> {
  final Value<String> symbol;
  final Value<String> source;
  final Value<String> currency;
  final Value<String> price;
  final Value<String?> previousClose;
  final Value<String?> openPrice;
  final Value<String?> dayHigh;
  final Value<String?> dayLow;
  final Value<int?> volume;
  final Value<String?> exchange;
  final Value<DateTime> asOf;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const MarketQuotesCompanion({
    this.symbol = const Value.absent(),
    this.source = const Value.absent(),
    this.currency = const Value.absent(),
    this.price = const Value.absent(),
    this.previousClose = const Value.absent(),
    this.openPrice = const Value.absent(),
    this.dayHigh = const Value.absent(),
    this.dayLow = const Value.absent(),
    this.volume = const Value.absent(),
    this.exchange = const Value.absent(),
    this.asOf = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MarketQuotesCompanion.insert({
    required String symbol,
    required String source,
    required String currency,
    required String price,
    this.previousClose = const Value.absent(),
    this.openPrice = const Value.absent(),
    this.dayHigh = const Value.absent(),
    this.dayLow = const Value.absent(),
    this.volume = const Value.absent(),
    this.exchange = const Value.absent(),
    required DateTime asOf,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : symbol = Value(symbol),
       source = Value(source),
       currency = Value(currency),
       price = Value(price),
       asOf = Value(asOf),
       fetchedAt = Value(fetchedAt);
  static Insertable<MarketQuoteRow> custom({
    Expression<String>? symbol,
    Expression<String>? source,
    Expression<String>? currency,
    Expression<String>? price,
    Expression<String>? previousClose,
    Expression<String>? openPrice,
    Expression<String>? dayHigh,
    Expression<String>? dayLow,
    Expression<int>? volume,
    Expression<String>? exchange,
    Expression<DateTime>? asOf,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (source != null) 'source': source,
      if (currency != null) 'currency': currency,
      if (price != null) 'price': price,
      if (previousClose != null) 'previous_close': previousClose,
      if (openPrice != null) 'open_price': openPrice,
      if (dayHigh != null) 'day_high': dayHigh,
      if (dayLow != null) 'day_low': dayLow,
      if (volume != null) 'volume': volume,
      if (exchange != null) 'exchange': exchange,
      if (asOf != null) 'as_of': asOf,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MarketQuotesCompanion copyWith({
    Value<String>? symbol,
    Value<String>? source,
    Value<String>? currency,
    Value<String>? price,
    Value<String?>? previousClose,
    Value<String?>? openPrice,
    Value<String?>? dayHigh,
    Value<String?>? dayLow,
    Value<int?>? volume,
    Value<String?>? exchange,
    Value<DateTime>? asOf,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return MarketQuotesCompanion(
      symbol: symbol ?? this.symbol,
      source: source ?? this.source,
      currency: currency ?? this.currency,
      price: price ?? this.price,
      previousClose: previousClose ?? this.previousClose,
      openPrice: openPrice ?? this.openPrice,
      dayHigh: dayHigh ?? this.dayHigh,
      dayLow: dayLow ?? this.dayLow,
      volume: volume ?? this.volume,
      exchange: exchange ?? this.exchange,
      asOf: asOf ?? this.asOf,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (price.present) {
      map['price'] = Variable<String>(price.value);
    }
    if (previousClose.present) {
      map['previous_close'] = Variable<String>(previousClose.value);
    }
    if (openPrice.present) {
      map['open_price'] = Variable<String>(openPrice.value);
    }
    if (dayHigh.present) {
      map['day_high'] = Variable<String>(dayHigh.value);
    }
    if (dayLow.present) {
      map['day_low'] = Variable<String>(dayLow.value);
    }
    if (volume.present) {
      map['volume'] = Variable<int>(volume.value);
    }
    if (exchange.present) {
      map['exchange'] = Variable<String>(exchange.value);
    }
    if (asOf.present) {
      map['as_of'] = Variable<DateTime>(asOf.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MarketQuotesCompanion(')
          ..write('symbol: $symbol, ')
          ..write('source: $source, ')
          ..write('currency: $currency, ')
          ..write('price: $price, ')
          ..write('previousClose: $previousClose, ')
          ..write('openPrice: $openPrice, ')
          ..write('dayHigh: $dayHigh, ')
          ..write('dayLow: $dayLow, ')
          ..write('volume: $volume, ')
          ..write('exchange: $exchange, ')
          ..write('asOf: $asOf, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MarketHistoryBarsTable extends MarketHistoryBars
    with TableInfo<$MarketHistoryBarsTable, MarketHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MarketHistoryBarsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intervalMeta = const VerificationMeta(
    'interval',
  );
  @override
  late final GeneratedColumn<String> interval = GeneratedColumn<String>(
    'interval',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _asOfMeta = const VerificationMeta('asOf');
  @override
  late final GeneratedColumn<DateTime> asOf = GeneratedColumn<DateTime>(
    'as_of',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openPriceMeta = const VerificationMeta(
    'openPrice',
  );
  @override
  late final GeneratedColumn<String> openPrice = GeneratedColumn<String>(
    'open_price',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _highMeta = const VerificationMeta('high');
  @override
  late final GeneratedColumn<String> high = GeneratedColumn<String>(
    'high',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lowMeta = const VerificationMeta('low');
  @override
  late final GeneratedColumn<String> low = GeneratedColumn<String>(
    'low',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _closePriceMeta = const VerificationMeta(
    'closePrice',
  );
  @override
  late final GeneratedColumn<String> closePrice = GeneratedColumn<String>(
    'close_price',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<int> volume = GeneratedColumn<int>(
    'volume',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _adjustedCloseMeta = const VerificationMeta(
    'adjustedClose',
  );
  @override
  late final GeneratedColumn<String> adjustedClose = GeneratedColumn<String>(
    'adjusted_close',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    symbol,
    interval,
    asOf,
    source,
    openPrice,
    high,
    low,
    closePrice,
    volume,
    adjustedClose,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'market_history_bars';
  @override
  VerificationContext validateIntegrity(
    Insertable<MarketHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('interval')) {
      context.handle(
        _intervalMeta,
        interval.isAcceptableOrUnknown(data['interval']!, _intervalMeta),
      );
    } else if (isInserting) {
      context.missing(_intervalMeta);
    }
    if (data.containsKey('as_of')) {
      context.handle(
        _asOfMeta,
        asOf.isAcceptableOrUnknown(data['as_of']!, _asOfMeta),
      );
    } else if (isInserting) {
      context.missing(_asOfMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('open_price')) {
      context.handle(
        _openPriceMeta,
        openPrice.isAcceptableOrUnknown(data['open_price']!, _openPriceMeta),
      );
    } else if (isInserting) {
      context.missing(_openPriceMeta);
    }
    if (data.containsKey('high')) {
      context.handle(
        _highMeta,
        high.isAcceptableOrUnknown(data['high']!, _highMeta),
      );
    } else if (isInserting) {
      context.missing(_highMeta);
    }
    if (data.containsKey('low')) {
      context.handle(
        _lowMeta,
        low.isAcceptableOrUnknown(data['low']!, _lowMeta),
      );
    } else if (isInserting) {
      context.missing(_lowMeta);
    }
    if (data.containsKey('close_price')) {
      context.handle(
        _closePriceMeta,
        closePrice.isAcceptableOrUnknown(data['close_price']!, _closePriceMeta),
      );
    } else if (isInserting) {
      context.missing(_closePriceMeta);
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    }
    if (data.containsKey('adjusted_close')) {
      context.handle(
        _adjustedCloseMeta,
        adjustedClose.isAcceptableOrUnknown(
          data['adjusted_close']!,
          _adjustedCloseMeta,
        ),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {symbol, interval, asOf, source};
  @override
  MarketHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MarketHistoryRow(
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      interval: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}interval'],
      )!,
      asOf: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}as_of'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      openPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}open_price'],
      )!,
      high: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}high'],
      )!,
      low: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}low'],
      )!,
      closePrice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}close_price'],
      )!,
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}volume'],
      ),
      adjustedClose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}adjusted_close'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $MarketHistoryBarsTable createAlias(String alias) {
    return $MarketHistoryBarsTable(attachedDatabase, alias);
  }
}

class MarketHistoryRow extends DataClass
    implements Insertable<MarketHistoryRow> {
  final String symbol;
  final String interval;
  final DateTime asOf;
  final String source;
  final String openPrice;
  final String high;
  final String low;
  final String closePrice;
  final int? volume;
  final String? adjustedClose;
  final DateTime fetchedAt;
  const MarketHistoryRow({
    required this.symbol,
    required this.interval,
    required this.asOf,
    required this.source,
    required this.openPrice,
    required this.high,
    required this.low,
    required this.closePrice,
    this.volume,
    this.adjustedClose,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['symbol'] = Variable<String>(symbol);
    map['interval'] = Variable<String>(interval);
    map['as_of'] = Variable<DateTime>(asOf);
    map['source'] = Variable<String>(source);
    map['open_price'] = Variable<String>(openPrice);
    map['high'] = Variable<String>(high);
    map['low'] = Variable<String>(low);
    map['close_price'] = Variable<String>(closePrice);
    if (!nullToAbsent || volume != null) {
      map['volume'] = Variable<int>(volume);
    }
    if (!nullToAbsent || adjustedClose != null) {
      map['adjusted_close'] = Variable<String>(adjustedClose);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  MarketHistoryBarsCompanion toCompanion(bool nullToAbsent) {
    return MarketHistoryBarsCompanion(
      symbol: Value(symbol),
      interval: Value(interval),
      asOf: Value(asOf),
      source: Value(source),
      openPrice: Value(openPrice),
      high: Value(high),
      low: Value(low),
      closePrice: Value(closePrice),
      volume: volume == null && nullToAbsent
          ? const Value.absent()
          : Value(volume),
      adjustedClose: adjustedClose == null && nullToAbsent
          ? const Value.absent()
          : Value(adjustedClose),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory MarketHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MarketHistoryRow(
      symbol: serializer.fromJson<String>(json['symbol']),
      interval: serializer.fromJson<String>(json['interval']),
      asOf: serializer.fromJson<DateTime>(json['asOf']),
      source: serializer.fromJson<String>(json['source']),
      openPrice: serializer.fromJson<String>(json['openPrice']),
      high: serializer.fromJson<String>(json['high']),
      low: serializer.fromJson<String>(json['low']),
      closePrice: serializer.fromJson<String>(json['closePrice']),
      volume: serializer.fromJson<int?>(json['volume']),
      adjustedClose: serializer.fromJson<String?>(json['adjustedClose']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'interval': serializer.toJson<String>(interval),
      'asOf': serializer.toJson<DateTime>(asOf),
      'source': serializer.toJson<String>(source),
      'openPrice': serializer.toJson<String>(openPrice),
      'high': serializer.toJson<String>(high),
      'low': serializer.toJson<String>(low),
      'closePrice': serializer.toJson<String>(closePrice),
      'volume': serializer.toJson<int?>(volume),
      'adjustedClose': serializer.toJson<String?>(adjustedClose),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  MarketHistoryRow copyWith({
    String? symbol,
    String? interval,
    DateTime? asOf,
    String? source,
    String? openPrice,
    String? high,
    String? low,
    String? closePrice,
    Value<int?> volume = const Value.absent(),
    Value<String?> adjustedClose = const Value.absent(),
    DateTime? fetchedAt,
  }) => MarketHistoryRow(
    symbol: symbol ?? this.symbol,
    interval: interval ?? this.interval,
    asOf: asOf ?? this.asOf,
    source: source ?? this.source,
    openPrice: openPrice ?? this.openPrice,
    high: high ?? this.high,
    low: low ?? this.low,
    closePrice: closePrice ?? this.closePrice,
    volume: volume.present ? volume.value : this.volume,
    adjustedClose: adjustedClose.present
        ? adjustedClose.value
        : this.adjustedClose,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  MarketHistoryRow copyWithCompanion(MarketHistoryBarsCompanion data) {
    return MarketHistoryRow(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      interval: data.interval.present ? data.interval.value : this.interval,
      asOf: data.asOf.present ? data.asOf.value : this.asOf,
      source: data.source.present ? data.source.value : this.source,
      openPrice: data.openPrice.present ? data.openPrice.value : this.openPrice,
      high: data.high.present ? data.high.value : this.high,
      low: data.low.present ? data.low.value : this.low,
      closePrice: data.closePrice.present
          ? data.closePrice.value
          : this.closePrice,
      volume: data.volume.present ? data.volume.value : this.volume,
      adjustedClose: data.adjustedClose.present
          ? data.adjustedClose.value
          : this.adjustedClose,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MarketHistoryRow(')
          ..write('symbol: $symbol, ')
          ..write('interval: $interval, ')
          ..write('asOf: $asOf, ')
          ..write('source: $source, ')
          ..write('openPrice: $openPrice, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('closePrice: $closePrice, ')
          ..write('volume: $volume, ')
          ..write('adjustedClose: $adjustedClose, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    interval,
    asOf,
    source,
    openPrice,
    high,
    low,
    closePrice,
    volume,
    adjustedClose,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MarketHistoryRow &&
          other.symbol == this.symbol &&
          other.interval == this.interval &&
          other.asOf == this.asOf &&
          other.source == this.source &&
          other.openPrice == this.openPrice &&
          other.high == this.high &&
          other.low == this.low &&
          other.closePrice == this.closePrice &&
          other.volume == this.volume &&
          other.adjustedClose == this.adjustedClose &&
          other.fetchedAt == this.fetchedAt);
}

class MarketHistoryBarsCompanion extends UpdateCompanion<MarketHistoryRow> {
  final Value<String> symbol;
  final Value<String> interval;
  final Value<DateTime> asOf;
  final Value<String> source;
  final Value<String> openPrice;
  final Value<String> high;
  final Value<String> low;
  final Value<String> closePrice;
  final Value<int?> volume;
  final Value<String?> adjustedClose;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const MarketHistoryBarsCompanion({
    this.symbol = const Value.absent(),
    this.interval = const Value.absent(),
    this.asOf = const Value.absent(),
    this.source = const Value.absent(),
    this.openPrice = const Value.absent(),
    this.high = const Value.absent(),
    this.low = const Value.absent(),
    this.closePrice = const Value.absent(),
    this.volume = const Value.absent(),
    this.adjustedClose = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MarketHistoryBarsCompanion.insert({
    required String symbol,
    required String interval,
    required DateTime asOf,
    required String source,
    required String openPrice,
    required String high,
    required String low,
    required String closePrice,
    this.volume = const Value.absent(),
    this.adjustedClose = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : symbol = Value(symbol),
       interval = Value(interval),
       asOf = Value(asOf),
       source = Value(source),
       openPrice = Value(openPrice),
       high = Value(high),
       low = Value(low),
       closePrice = Value(closePrice),
       fetchedAt = Value(fetchedAt);
  static Insertable<MarketHistoryRow> custom({
    Expression<String>? symbol,
    Expression<String>? interval,
    Expression<DateTime>? asOf,
    Expression<String>? source,
    Expression<String>? openPrice,
    Expression<String>? high,
    Expression<String>? low,
    Expression<String>? closePrice,
    Expression<int>? volume,
    Expression<String>? adjustedClose,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (interval != null) 'interval': interval,
      if (asOf != null) 'as_of': asOf,
      if (source != null) 'source': source,
      if (openPrice != null) 'open_price': openPrice,
      if (high != null) 'high': high,
      if (low != null) 'low': low,
      if (closePrice != null) 'close_price': closePrice,
      if (volume != null) 'volume': volume,
      if (adjustedClose != null) 'adjusted_close': adjustedClose,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MarketHistoryBarsCompanion copyWith({
    Value<String>? symbol,
    Value<String>? interval,
    Value<DateTime>? asOf,
    Value<String>? source,
    Value<String>? openPrice,
    Value<String>? high,
    Value<String>? low,
    Value<String>? closePrice,
    Value<int?>? volume,
    Value<String?>? adjustedClose,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return MarketHistoryBarsCompanion(
      symbol: symbol ?? this.symbol,
      interval: interval ?? this.interval,
      asOf: asOf ?? this.asOf,
      source: source ?? this.source,
      openPrice: openPrice ?? this.openPrice,
      high: high ?? this.high,
      low: low ?? this.low,
      closePrice: closePrice ?? this.closePrice,
      volume: volume ?? this.volume,
      adjustedClose: adjustedClose ?? this.adjustedClose,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (interval.present) {
      map['interval'] = Variable<String>(interval.value);
    }
    if (asOf.present) {
      map['as_of'] = Variable<DateTime>(asOf.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (openPrice.present) {
      map['open_price'] = Variable<String>(openPrice.value);
    }
    if (high.present) {
      map['high'] = Variable<String>(high.value);
    }
    if (low.present) {
      map['low'] = Variable<String>(low.value);
    }
    if (closePrice.present) {
      map['close_price'] = Variable<String>(closePrice.value);
    }
    if (volume.present) {
      map['volume'] = Variable<int>(volume.value);
    }
    if (adjustedClose.present) {
      map['adjusted_close'] = Variable<String>(adjustedClose.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MarketHistoryBarsCompanion(')
          ..write('symbol: $symbol, ')
          ..write('interval: $interval, ')
          ..write('asOf: $asOf, ')
          ..write('source: $source, ')
          ..write('openPrice: $openPrice, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('closePrice: $closePrice, ')
          ..write('volume: $volume, ')
          ..write('adjustedClose: $adjustedClose, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MarketSymbolSearchesTable extends MarketSymbolSearches
    with TableInfo<$MarketSymbolSearchesTable, MarketSymbolSearchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MarketSymbolSearchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
    'query',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultsMeta = const VerificationMeta(
    'results',
  );
  @override
  late final GeneratedColumn<String> results = GeneratedColumn<String>(
    'results',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [query, source, results, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'market_symbol_searches';
  @override
  VerificationContext validateIntegrity(
    Insertable<MarketSymbolSearchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('query')) {
      context.handle(
        _queryMeta,
        query.isAcceptableOrUnknown(data['query']!, _queryMeta),
      );
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('results')) {
      context.handle(
        _resultsMeta,
        results.isAcceptableOrUnknown(data['results']!, _resultsMeta),
      );
    } else if (isInserting) {
      context.missing(_resultsMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {query, source};
  @override
  MarketSymbolSearchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MarketSymbolSearchRow(
      query: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      results: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}results'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $MarketSymbolSearchesTable createAlias(String alias) {
    return $MarketSymbolSearchesTable(attachedDatabase, alias);
  }
}

class MarketSymbolSearchRow extends DataClass
    implements Insertable<MarketSymbolSearchRow> {
  final String query;
  final String source;
  final String results;
  final DateTime fetchedAt;
  const MarketSymbolSearchRow({
    required this.query,
    required this.source,
    required this.results,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['query'] = Variable<String>(query);
    map['source'] = Variable<String>(source);
    map['results'] = Variable<String>(results);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  MarketSymbolSearchesCompanion toCompanion(bool nullToAbsent) {
    return MarketSymbolSearchesCompanion(
      query: Value(query),
      source: Value(source),
      results: Value(results),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory MarketSymbolSearchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MarketSymbolSearchRow(
      query: serializer.fromJson<String>(json['query']),
      source: serializer.fromJson<String>(json['source']),
      results: serializer.fromJson<String>(json['results']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'query': serializer.toJson<String>(query),
      'source': serializer.toJson<String>(source),
      'results': serializer.toJson<String>(results),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  MarketSymbolSearchRow copyWith({
    String? query,
    String? source,
    String? results,
    DateTime? fetchedAt,
  }) => MarketSymbolSearchRow(
    query: query ?? this.query,
    source: source ?? this.source,
    results: results ?? this.results,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  MarketSymbolSearchRow copyWithCompanion(MarketSymbolSearchesCompanion data) {
    return MarketSymbolSearchRow(
      query: data.query.present ? data.query.value : this.query,
      source: data.source.present ? data.source.value : this.source,
      results: data.results.present ? data.results.value : this.results,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MarketSymbolSearchRow(')
          ..write('query: $query, ')
          ..write('source: $source, ')
          ..write('results: $results, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(query, source, results, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MarketSymbolSearchRow &&
          other.query == this.query &&
          other.source == this.source &&
          other.results == this.results &&
          other.fetchedAt == this.fetchedAt);
}

class MarketSymbolSearchesCompanion
    extends UpdateCompanion<MarketSymbolSearchRow> {
  final Value<String> query;
  final Value<String> source;
  final Value<String> results;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const MarketSymbolSearchesCompanion({
    this.query = const Value.absent(),
    this.source = const Value.absent(),
    this.results = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MarketSymbolSearchesCompanion.insert({
    required String query,
    required String source,
    required String results,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : query = Value(query),
       source = Value(source),
       results = Value(results),
       fetchedAt = Value(fetchedAt);
  static Insertable<MarketSymbolSearchRow> custom({
    Expression<String>? query,
    Expression<String>? source,
    Expression<String>? results,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (query != null) 'query': query,
      if (source != null) 'source': source,
      if (results != null) 'results': results,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MarketSymbolSearchesCompanion copyWith({
    Value<String>? query,
    Value<String>? source,
    Value<String>? results,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return MarketSymbolSearchesCompanion(
      query: query ?? this.query,
      source: source ?? this.source,
      results: results ?? this.results,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (results.present) {
      map['results'] = Variable<String>(results.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MarketSymbolSearchesCompanion(')
          ..write('query: $query, ')
          ..write('source: $source, ')
          ..write('results: $results, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SecuritiesCatalogTable extends SecuritiesCatalog
    with TableInfo<$SecuritiesCatalogTable, SecuritiesCatalogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SecuritiesCatalogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _marketMeta = const VerificationMeta('market');
  @override
  late final GeneratedColumn<String> market = GeneratedColumn<String>(
    'market',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AssetType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AssetType>($SecuritiesCatalogTable.$convertertype);
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameEnMeta = const VerificationMeta('nameEn');
  @override
  late final GeneratedColumn<String> nameEn = GeneratedColumn<String>(
    'name_en',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameCnMeta = const VerificationMeta('nameCn');
  @override
  late final GeneratedColumn<String> nameCn = GeneratedColumn<String>(
    'name_cn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinyinMeta = const VerificationMeta('pinyin');
  @override
  late final GeneratedColumn<String> pinyin = GeneratedColumn<String>(
    'pinyin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinyinInitialsMeta = const VerificationMeta(
    'pinyinInitials',
  );
  @override
  late final GeneratedColumn<String> pinyinInitials = GeneratedColumn<String>(
    'pinyin_initials',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aliasesMeta = const VerificationMeta(
    'aliases',
  );
  @override
  late final GeneratedColumn<String> aliases = GeneratedColumn<String>(
    'aliases',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    symbol,
    market,
    type,
    currency,
    nameEn,
    nameCn,
    pinyin,
    pinyinInitials,
    aliases,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'securities_catalog';
  @override
  VerificationContext validateIntegrity(
    Insertable<SecuritiesCatalogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('market')) {
      context.handle(
        _marketMeta,
        market.isAcceptableOrUnknown(data['market']!, _marketMeta),
      );
    } else if (isInserting) {
      context.missing(_marketMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('name_en')) {
      context.handle(
        _nameEnMeta,
        nameEn.isAcceptableOrUnknown(data['name_en']!, _nameEnMeta),
      );
    }
    if (data.containsKey('name_cn')) {
      context.handle(
        _nameCnMeta,
        nameCn.isAcceptableOrUnknown(data['name_cn']!, _nameCnMeta),
      );
    }
    if (data.containsKey('pinyin')) {
      context.handle(
        _pinyinMeta,
        pinyin.isAcceptableOrUnknown(data['pinyin']!, _pinyinMeta),
      );
    }
    if (data.containsKey('pinyin_initials')) {
      context.handle(
        _pinyinInitialsMeta,
        pinyinInitials.isAcceptableOrUnknown(
          data['pinyin_initials']!,
          _pinyinInitialsMeta,
        ),
      );
    }
    if (data.containsKey('aliases')) {
      context.handle(
        _aliasesMeta,
        aliases.isAcceptableOrUnknown(data['aliases']!, _aliasesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SecuritiesCatalogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SecuritiesCatalogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      market: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}market'],
      )!,
      type: $SecuritiesCatalogTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      nameEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_en'],
      ),
      nameCn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_cn'],
      ),
      pinyin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pinyin'],
      ),
      pinyinInitials: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pinyin_initials'],
      ),
      aliases: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aliases'],
      ),
    );
  }

  @override
  $SecuritiesCatalogTable createAlias(String alias) {
    return $SecuritiesCatalogTable(attachedDatabase, alias);
  }

  static TypeConverter<AssetType, String> $convertertype =
      const EnumStringConverter(AssetType.values);
}

class SecuritiesCatalogRow extends DataClass
    implements Insertable<SecuritiesCatalogRow> {
  final String id;
  final String symbol;

  /// Wire-form market label (`cn_a`, `us_stock`, …). Matches the value
  /// space `assets.market` uses, so dedupe by `(market, symbol)` against
  /// owned assets is a plain string compare and never has to round-trip
  /// through `AssetMarket`.
  final String market;
  final AssetType type;
  final String currency;
  final String? nameEn;
  final String? nameCn;

  /// Lower-cased full pinyin without tone marks, no separators
  /// (e.g. `guizhoumaotai`). Matches typed-as-pinyin queries
  /// (`gzmaotai`, `kweichowmoutai`).
  final String? pinyin;

  /// Pinyin initials, no separators (e.g. `gzmt`). Matches the very
  /// common abbreviated-pinyin search style.
  final String? pinyinInitials;

  /// Whitespace-separated bag of additional searchable terms — common
  /// short forms, English aliases, ticker variants. Indexed by FTS5 like
  /// any other column; kept out of the four canonical name fields so
  /// rank doesn't get diluted on exact lookups.
  final String? aliases;
  const SecuritiesCatalogRow({
    required this.id,
    required this.symbol,
    required this.market,
    required this.type,
    required this.currency,
    this.nameEn,
    this.nameCn,
    this.pinyin,
    this.pinyinInitials,
    this.aliases,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['symbol'] = Variable<String>(symbol);
    map['market'] = Variable<String>(market);
    {
      map['type'] = Variable<String>(
        $SecuritiesCatalogTable.$convertertype.toSql(type),
      );
    }
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || nameEn != null) {
      map['name_en'] = Variable<String>(nameEn);
    }
    if (!nullToAbsent || nameCn != null) {
      map['name_cn'] = Variable<String>(nameCn);
    }
    if (!nullToAbsent || pinyin != null) {
      map['pinyin'] = Variable<String>(pinyin);
    }
    if (!nullToAbsent || pinyinInitials != null) {
      map['pinyin_initials'] = Variable<String>(pinyinInitials);
    }
    if (!nullToAbsent || aliases != null) {
      map['aliases'] = Variable<String>(aliases);
    }
    return map;
  }

  SecuritiesCatalogCompanion toCompanion(bool nullToAbsent) {
    return SecuritiesCatalogCompanion(
      id: Value(id),
      symbol: Value(symbol),
      market: Value(market),
      type: Value(type),
      currency: Value(currency),
      nameEn: nameEn == null && nullToAbsent
          ? const Value.absent()
          : Value(nameEn),
      nameCn: nameCn == null && nullToAbsent
          ? const Value.absent()
          : Value(nameCn),
      pinyin: pinyin == null && nullToAbsent
          ? const Value.absent()
          : Value(pinyin),
      pinyinInitials: pinyinInitials == null && nullToAbsent
          ? const Value.absent()
          : Value(pinyinInitials),
      aliases: aliases == null && nullToAbsent
          ? const Value.absent()
          : Value(aliases),
    );
  }

  factory SecuritiesCatalogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SecuritiesCatalogRow(
      id: serializer.fromJson<String>(json['id']),
      symbol: serializer.fromJson<String>(json['symbol']),
      market: serializer.fromJson<String>(json['market']),
      type: serializer.fromJson<AssetType>(json['type']),
      currency: serializer.fromJson<String>(json['currency']),
      nameEn: serializer.fromJson<String?>(json['nameEn']),
      nameCn: serializer.fromJson<String?>(json['nameCn']),
      pinyin: serializer.fromJson<String?>(json['pinyin']),
      pinyinInitials: serializer.fromJson<String?>(json['pinyinInitials']),
      aliases: serializer.fromJson<String?>(json['aliases']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'symbol': serializer.toJson<String>(symbol),
      'market': serializer.toJson<String>(market),
      'type': serializer.toJson<AssetType>(type),
      'currency': serializer.toJson<String>(currency),
      'nameEn': serializer.toJson<String?>(nameEn),
      'nameCn': serializer.toJson<String?>(nameCn),
      'pinyin': serializer.toJson<String?>(pinyin),
      'pinyinInitials': serializer.toJson<String?>(pinyinInitials),
      'aliases': serializer.toJson<String?>(aliases),
    };
  }

  SecuritiesCatalogRow copyWith({
    String? id,
    String? symbol,
    String? market,
    AssetType? type,
    String? currency,
    Value<String?> nameEn = const Value.absent(),
    Value<String?> nameCn = const Value.absent(),
    Value<String?> pinyin = const Value.absent(),
    Value<String?> pinyinInitials = const Value.absent(),
    Value<String?> aliases = const Value.absent(),
  }) => SecuritiesCatalogRow(
    id: id ?? this.id,
    symbol: symbol ?? this.symbol,
    market: market ?? this.market,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    nameEn: nameEn.present ? nameEn.value : this.nameEn,
    nameCn: nameCn.present ? nameCn.value : this.nameCn,
    pinyin: pinyin.present ? pinyin.value : this.pinyin,
    pinyinInitials: pinyinInitials.present
        ? pinyinInitials.value
        : this.pinyinInitials,
    aliases: aliases.present ? aliases.value : this.aliases,
  );
  SecuritiesCatalogRow copyWithCompanion(SecuritiesCatalogCompanion data) {
    return SecuritiesCatalogRow(
      id: data.id.present ? data.id.value : this.id,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      market: data.market.present ? data.market.value : this.market,
      type: data.type.present ? data.type.value : this.type,
      currency: data.currency.present ? data.currency.value : this.currency,
      nameEn: data.nameEn.present ? data.nameEn.value : this.nameEn,
      nameCn: data.nameCn.present ? data.nameCn.value : this.nameCn,
      pinyin: data.pinyin.present ? data.pinyin.value : this.pinyin,
      pinyinInitials: data.pinyinInitials.present
          ? data.pinyinInitials.value
          : this.pinyinInitials,
      aliases: data.aliases.present ? data.aliases.value : this.aliases,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SecuritiesCatalogRow(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('market: $market, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('nameEn: $nameEn, ')
          ..write('nameCn: $nameCn, ')
          ..write('pinyin: $pinyin, ')
          ..write('pinyinInitials: $pinyinInitials, ')
          ..write('aliases: $aliases')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    symbol,
    market,
    type,
    currency,
    nameEn,
    nameCn,
    pinyin,
    pinyinInitials,
    aliases,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SecuritiesCatalogRow &&
          other.id == this.id &&
          other.symbol == this.symbol &&
          other.market == this.market &&
          other.type == this.type &&
          other.currency == this.currency &&
          other.nameEn == this.nameEn &&
          other.nameCn == this.nameCn &&
          other.pinyin == this.pinyin &&
          other.pinyinInitials == this.pinyinInitials &&
          other.aliases == this.aliases);
}

class SecuritiesCatalogCompanion extends UpdateCompanion<SecuritiesCatalogRow> {
  final Value<String> id;
  final Value<String> symbol;
  final Value<String> market;
  final Value<AssetType> type;
  final Value<String> currency;
  final Value<String?> nameEn;
  final Value<String?> nameCn;
  final Value<String?> pinyin;
  final Value<String?> pinyinInitials;
  final Value<String?> aliases;
  final Value<int> rowid;
  const SecuritiesCatalogCompanion({
    this.id = const Value.absent(),
    this.symbol = const Value.absent(),
    this.market = const Value.absent(),
    this.type = const Value.absent(),
    this.currency = const Value.absent(),
    this.nameEn = const Value.absent(),
    this.nameCn = const Value.absent(),
    this.pinyin = const Value.absent(),
    this.pinyinInitials = const Value.absent(),
    this.aliases = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SecuritiesCatalogCompanion.insert({
    required String id,
    required String symbol,
    required String market,
    required AssetType type,
    required String currency,
    this.nameEn = const Value.absent(),
    this.nameCn = const Value.absent(),
    this.pinyin = const Value.absent(),
    this.pinyinInitials = const Value.absent(),
    this.aliases = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       symbol = Value(symbol),
       market = Value(market),
       type = Value(type),
       currency = Value(currency);
  static Insertable<SecuritiesCatalogRow> custom({
    Expression<String>? id,
    Expression<String>? symbol,
    Expression<String>? market,
    Expression<String>? type,
    Expression<String>? currency,
    Expression<String>? nameEn,
    Expression<String>? nameCn,
    Expression<String>? pinyin,
    Expression<String>? pinyinInitials,
    Expression<String>? aliases,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (symbol != null) 'symbol': symbol,
      if (market != null) 'market': market,
      if (type != null) 'type': type,
      if (currency != null) 'currency': currency,
      if (nameEn != null) 'name_en': nameEn,
      if (nameCn != null) 'name_cn': nameCn,
      if (pinyin != null) 'pinyin': pinyin,
      if (pinyinInitials != null) 'pinyin_initials': pinyinInitials,
      if (aliases != null) 'aliases': aliases,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SecuritiesCatalogCompanion copyWith({
    Value<String>? id,
    Value<String>? symbol,
    Value<String>? market,
    Value<AssetType>? type,
    Value<String>? currency,
    Value<String?>? nameEn,
    Value<String?>? nameCn,
    Value<String?>? pinyin,
    Value<String?>? pinyinInitials,
    Value<String?>? aliases,
    Value<int>? rowid,
  }) {
    return SecuritiesCatalogCompanion(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      market: market ?? this.market,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      nameEn: nameEn ?? this.nameEn,
      nameCn: nameCn ?? this.nameCn,
      pinyin: pinyin ?? this.pinyin,
      pinyinInitials: pinyinInitials ?? this.pinyinInitials,
      aliases: aliases ?? this.aliases,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (market.present) {
      map['market'] = Variable<String>(market.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $SecuritiesCatalogTable.$convertertype.toSql(type.value),
      );
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (nameEn.present) {
      map['name_en'] = Variable<String>(nameEn.value);
    }
    if (nameCn.present) {
      map['name_cn'] = Variable<String>(nameCn.value);
    }
    if (pinyin.present) {
      map['pinyin'] = Variable<String>(pinyin.value);
    }
    if (pinyinInitials.present) {
      map['pinyin_initials'] = Variable<String>(pinyinInitials.value);
    }
    if (aliases.present) {
      map['aliases'] = Variable<String>(aliases.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SecuritiesCatalogCompanion(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('market: $market, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('nameEn: $nameEn, ')
          ..write('nameCn: $nameCn, ')
          ..write('pinyin: $pinyin, ')
          ..write('pinyinInitials: $pinyinInitials, ')
          ..write('aliases: $aliases, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SecuritiesCatalogMetaTable extends SecuritiesCatalogMeta
    with TableInfo<$SecuritiesCatalogMetaTable, SecuritiesCatalogMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SecuritiesCatalogMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  @override
  late final GeneratedColumn<String> checksum = GeneratedColumn<String>(
    'checksum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowCountMeta = const VerificationMeta(
    'rowCount',
  );
  @override
  late final GeneratedColumn<int> rowCount = GeneratedColumn<int>(
    'row_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loadedAtMeta = const VerificationMeta(
    'loadedAt',
  );
  @override
  late final GeneratedColumn<DateTime> loadedAt = GeneratedColumn<DateTime>(
    'loaded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    checksum,
    rowCount,
    loadedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'securities_catalog_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SecuritiesCatalogMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    } else if (isInserting) {
      context.missing(_checksumMeta);
    }
    if (data.containsKey('row_count')) {
      context.handle(
        _rowCountMeta,
        rowCount.isAcceptableOrUnknown(data['row_count']!, _rowCountMeta),
      );
    } else if (isInserting) {
      context.missing(_rowCountMeta);
    }
    if (data.containsKey('loaded_at')) {
      context.handle(
        _loadedAtMeta,
        loadedAt.isAcceptableOrUnknown(data['loaded_at']!, _loadedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_loadedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SecuritiesCatalogMetaRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SecuritiesCatalogMetaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum'],
      )!,
      rowCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_count'],
      )!,
      loadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}loaded_at'],
      )!,
    );
  }

  @override
  $SecuritiesCatalogMetaTable createAlias(String alias) {
    return $SecuritiesCatalogMetaTable(attachedDatabase, alias);
  }
}

class SecuritiesCatalogMetaRow extends DataClass
    implements Insertable<SecuritiesCatalogMetaRow> {
  final int id;
  final String version;
  final String checksum;
  final int rowCount;
  final DateTime loadedAt;
  const SecuritiesCatalogMetaRow({
    required this.id,
    required this.version,
    required this.checksum,
    required this.rowCount,
    required this.loadedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['version'] = Variable<String>(version);
    map['checksum'] = Variable<String>(checksum);
    map['row_count'] = Variable<int>(rowCount);
    map['loaded_at'] = Variable<DateTime>(loadedAt);
    return map;
  }

  SecuritiesCatalogMetaCompanion toCompanion(bool nullToAbsent) {
    return SecuritiesCatalogMetaCompanion(
      id: Value(id),
      version: Value(version),
      checksum: Value(checksum),
      rowCount: Value(rowCount),
      loadedAt: Value(loadedAt),
    );
  }

  factory SecuritiesCatalogMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SecuritiesCatalogMetaRow(
      id: serializer.fromJson<int>(json['id']),
      version: serializer.fromJson<String>(json['version']),
      checksum: serializer.fromJson<String>(json['checksum']),
      rowCount: serializer.fromJson<int>(json['rowCount']),
      loadedAt: serializer.fromJson<DateTime>(json['loadedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'version': serializer.toJson<String>(version),
      'checksum': serializer.toJson<String>(checksum),
      'rowCount': serializer.toJson<int>(rowCount),
      'loadedAt': serializer.toJson<DateTime>(loadedAt),
    };
  }

  SecuritiesCatalogMetaRow copyWith({
    int? id,
    String? version,
    String? checksum,
    int? rowCount,
    DateTime? loadedAt,
  }) => SecuritiesCatalogMetaRow(
    id: id ?? this.id,
    version: version ?? this.version,
    checksum: checksum ?? this.checksum,
    rowCount: rowCount ?? this.rowCount,
    loadedAt: loadedAt ?? this.loadedAt,
  );
  SecuritiesCatalogMetaRow copyWithCompanion(
    SecuritiesCatalogMetaCompanion data,
  ) {
    return SecuritiesCatalogMetaRow(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
      rowCount: data.rowCount.present ? data.rowCount.value : this.rowCount,
      loadedAt: data.loadedAt.present ? data.loadedAt.value : this.loadedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SecuritiesCatalogMetaRow(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('checksum: $checksum, ')
          ..write('rowCount: $rowCount, ')
          ..write('loadedAt: $loadedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, version, checksum, rowCount, loadedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SecuritiesCatalogMetaRow &&
          other.id == this.id &&
          other.version == this.version &&
          other.checksum == this.checksum &&
          other.rowCount == this.rowCount &&
          other.loadedAt == this.loadedAt);
}

class SecuritiesCatalogMetaCompanion
    extends UpdateCompanion<SecuritiesCatalogMetaRow> {
  final Value<int> id;
  final Value<String> version;
  final Value<String> checksum;
  final Value<int> rowCount;
  final Value<DateTime> loadedAt;
  const SecuritiesCatalogMetaCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.checksum = const Value.absent(),
    this.rowCount = const Value.absent(),
    this.loadedAt = const Value.absent(),
  });
  SecuritiesCatalogMetaCompanion.insert({
    this.id = const Value.absent(),
    required String version,
    required String checksum,
    required int rowCount,
    required DateTime loadedAt,
  }) : version = Value(version),
       checksum = Value(checksum),
       rowCount = Value(rowCount),
       loadedAt = Value(loadedAt);
  static Insertable<SecuritiesCatalogMetaRow> custom({
    Expression<int>? id,
    Expression<String>? version,
    Expression<String>? checksum,
    Expression<int>? rowCount,
    Expression<DateTime>? loadedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (checksum != null) 'checksum': checksum,
      if (rowCount != null) 'row_count': rowCount,
      if (loadedAt != null) 'loaded_at': loadedAt,
    });
  }

  SecuritiesCatalogMetaCompanion copyWith({
    Value<int>? id,
    Value<String>? version,
    Value<String>? checksum,
    Value<int>? rowCount,
    Value<DateTime>? loadedAt,
  }) {
    return SecuritiesCatalogMetaCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      checksum: checksum ?? this.checksum,
      rowCount: rowCount ?? this.rowCount,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<String>(checksum.value);
    }
    if (rowCount.present) {
      map['row_count'] = Variable<int>(rowCount.value);
    }
    if (loadedAt.present) {
      map['loaded_at'] = Variable<DateTime>(loadedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SecuritiesCatalogMetaCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('checksum: $checksum, ')
          ..write('rowCount: $rowCount, ')
          ..write('loadedAt: $loadedAt')
          ..write(')'))
        .toString();
  }
}

class $JournalEntriesTable extends JournalEntries
    with TableInfo<$JournalEntriesTable, JournalEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($JournalEntriesTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _settledOnMeta = const VerificationMeta(
    'settledOn',
  );
  @override
  late final GeneratedColumn<DateTime> settledOn = GeneratedColumn<DateTime>(
    'settled_on',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _narrationMeta = const VerificationMeta(
    'narration',
  );
  @override
  late final GeneratedColumn<String> narration = GeneratedColumn<String>(
    'narration',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payeeMeta = const VerificationMeta('payee');
  @override
  late final GeneratedColumn<String> payee = GeneratedColumn<String>(
    'payee',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EntryFlag, String> flag =
      GeneratedColumn<String>(
        'flag',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(EntryFlag.confirmed.name),
      ).withConverter<EntryFlag>($JournalEntriesTable.$converterflag);
  static const VerificationMeta _tagIdsJsonMeta = const VerificationMeta(
    'tagIdsJson',
  );
  @override
  late final GeneratedColumn<String> tagIdsJson = GeneratedColumn<String>(
    'tag_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    date,
    settledOn,
    narration,
    payee,
    flag,
    tagIdsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('settled_on')) {
      context.handle(
        _settledOnMeta,
        settledOn.isAcceptableOrUnknown(data['settled_on']!, _settledOnMeta),
      );
    }
    if (data.containsKey('narration')) {
      context.handle(
        _narrationMeta,
        narration.isAcceptableOrUnknown(data['narration']!, _narrationMeta),
      );
    } else if (isInserting) {
      context.missing(_narrationMeta);
    }
    if (data.containsKey('payee')) {
      context.handle(
        _payeeMeta,
        payee.isAcceptableOrUnknown(data['payee']!, _payeeMeta),
      );
    }
    if (data.containsKey('tag_ids_json')) {
      context.handle(
        _tagIdsJsonMeta,
        tagIdsJson.isAcceptableOrUnknown(
          data['tag_ids_json']!,
          _tagIdsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JournalEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalEntryRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $JournalEntriesTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      settledOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}settled_on'],
      ),
      narration: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}narration'],
      )!,
      payee: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payee'],
      ),
      flag: $JournalEntriesTable.$converterflag.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}flag'],
        )!,
      ),
      tagIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_ids_json'],
      )!,
    );
  }

  @override
  $JournalEntriesTable createAlias(String alias) {
    return $JournalEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<EntryFlag, String> $converterflag =
      const EnumStringConverter(EntryFlag.values);
}

class JournalEntryRow extends DataClass implements Insertable<JournalEntryRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;

  /// Trade date — when the event happened. Stored as a regular Drift
  /// DateTime (seconds-since-epoch INTEGER) so range queries by date
  /// hit the index rather than triggering text-comparison sorts.
  final DateTime date;

  /// Settlement date (broker T+2 etc.). NULL when same-day.
  final DateTime? settledOn;

  /// Free-form description. Required and non-empty by convention so the
  /// timeline always has something to render; an empty string is
  /// reserved for the synthetic padding rows ([EntryFlag.padding]).
  final String narration;

  /// Optional counter-party (merchant / payer name). Not indexed —
  /// payee-driven views aggregate inside Dart since the surface is small.
  final String? payee;

  /// Beancount lifecycle flag. See `EntryFlag` in
  /// `domain/journal_entry.dart` for the value semantics.
  final EntryFlag flag;

  /// JSON-encoded list of `tags.id` strings. Denormalised onto the JE so
  /// reading entries doesn't require a join through `tag_links`. The
  /// canonical writer / reader are [JournalEntryRow] code paths only.
  final String tagIdsJson;
  const JournalEntryRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.date,
    this.settledOn,
    required this.narration,
    this.payee,
    required this.flag,
    required this.tagIdsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>(
        $JournalEntriesTable.$converterhlc.toSql(hlc),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || settledOn != null) {
      map['settled_on'] = Variable<DateTime>(settledOn);
    }
    map['narration'] = Variable<String>(narration);
    if (!nullToAbsent || payee != null) {
      map['payee'] = Variable<String>(payee);
    }
    {
      map['flag'] = Variable<String>(
        $JournalEntriesTable.$converterflag.toSql(flag),
      );
    }
    map['tag_ids_json'] = Variable<String>(tagIdsJson);
    return map;
  }

  JournalEntriesCompanion toCompanion(bool nullToAbsent) {
    return JournalEntriesCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      date: Value(date),
      settledOn: settledOn == null && nullToAbsent
          ? const Value.absent()
          : Value(settledOn),
      narration: Value(narration),
      payee: payee == null && nullToAbsent
          ? const Value.absent()
          : Value(payee),
      flag: Value(flag),
      tagIdsJson: Value(tagIdsJson),
    );
  }

  factory JournalEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalEntryRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      settledOn: serializer.fromJson<DateTime?>(json['settledOn']),
      narration: serializer.fromJson<String>(json['narration']),
      payee: serializer.fromJson<String?>(json['payee']),
      flag: serializer.fromJson<EntryFlag>(json['flag']),
      tagIdsJson: serializer.fromJson<String>(json['tagIdsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<DateTime>(date),
      'settledOn': serializer.toJson<DateTime?>(settledOn),
      'narration': serializer.toJson<String>(narration),
      'payee': serializer.toJson<String?>(payee),
      'flag': serializer.toJson<EntryFlag>(flag),
      'tagIdsJson': serializer.toJson<String>(tagIdsJson),
    };
  }

  JournalEntryRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    DateTime? date,
    Value<DateTime?> settledOn = const Value.absent(),
    String? narration,
    Value<String?> payee = const Value.absent(),
    EntryFlag? flag,
    String? tagIdsJson,
  }) => JournalEntryRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    date: date ?? this.date,
    settledOn: settledOn.present ? settledOn.value : this.settledOn,
    narration: narration ?? this.narration,
    payee: payee.present ? payee.value : this.payee,
    flag: flag ?? this.flag,
    tagIdsJson: tagIdsJson ?? this.tagIdsJson,
  );
  JournalEntryRow copyWithCompanion(JournalEntriesCompanion data) {
    return JournalEntryRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      settledOn: data.settledOn.present ? data.settledOn.value : this.settledOn,
      narration: data.narration.present ? data.narration.value : this.narration,
      payee: data.payee.present ? data.payee.value : this.payee,
      flag: data.flag.present ? data.flag.value : this.flag,
      tagIdsJson: data.tagIdsJson.present
          ? data.tagIdsJson.value
          : this.tagIdsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntryRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('settledOn: $settledOn, ')
          ..write('narration: $narration, ')
          ..write('payee: $payee, ')
          ..write('flag: $flag, ')
          ..write('tagIdsJson: $tagIdsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    date,
    settledOn,
    narration,
    payee,
    flag,
    tagIdsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalEntryRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.date == this.date &&
          other.settledOn == this.settledOn &&
          other.narration == this.narration &&
          other.payee == this.payee &&
          other.flag == this.flag &&
          other.tagIdsJson == this.tagIdsJson);
}

class JournalEntriesCompanion extends UpdateCompanion<JournalEntryRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<DateTime> date;
  final Value<DateTime?> settledOn;
  final Value<String> narration;
  final Value<String?> payee;
  final Value<EntryFlag> flag;
  final Value<String> tagIdsJson;
  final Value<int> rowid;
  const JournalEntriesCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.settledOn = const Value.absent(),
    this.narration = const Value.absent(),
    this.payee = const Value.absent(),
    this.flag = const Value.absent(),
    this.tagIdsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalEntriesCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required DateTime date,
    this.settledOn = const Value.absent(),
    required String narration,
    this.payee = const Value.absent(),
    this.flag = const Value.absent(),
    this.tagIdsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       date = Value(date),
       narration = Value(narration);
  static Insertable<JournalEntryRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<DateTime>? date,
    Expression<DateTime>? settledOn,
    Expression<String>? narration,
    Expression<String>? payee,
    Expression<String>? flag,
    Expression<String>? tagIdsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (settledOn != null) 'settled_on': settledOn,
      if (narration != null) 'narration': narration,
      if (payee != null) 'payee': payee,
      if (flag != null) 'flag': flag,
      if (tagIdsJson != null) 'tag_ids_json': tagIdsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JournalEntriesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<DateTime>? date,
    Value<DateTime?>? settledOn,
    Value<String>? narration,
    Value<String?>? payee,
    Value<EntryFlag>? flag,
    Value<String>? tagIdsJson,
    Value<int>? rowid,
  }) {
    return JournalEntriesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      date: date ?? this.date,
      settledOn: settledOn ?? this.settledOn,
      narration: narration ?? this.narration,
      payee: payee ?? this.payee,
      flag: flag ?? this.flag,
      tagIdsJson: tagIdsJson ?? this.tagIdsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $JournalEntriesTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (settledOn.present) {
      map['settled_on'] = Variable<DateTime>(settledOn.value);
    }
    if (narration.present) {
      map['narration'] = Variable<String>(narration.value);
    }
    if (payee.present) {
      map['payee'] = Variable<String>(payee.value);
    }
    if (flag.present) {
      map['flag'] = Variable<String>(
        $JournalEntriesTable.$converterflag.toSql(flag.value),
      );
    }
    if (tagIdsJson.present) {
      map['tag_ids_json'] = Variable<String>(tagIdsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntriesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('settledOn: $settledOn, ')
          ..write('narration: $narration, ')
          ..write('payee: $payee, ')
          ..write('flag: $flag, ')
          ..write('tagIdsJson: $tagIdsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PostingsTable extends Postings
    with TableInfo<$PostingsTable, PostingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PostingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($PostingsTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _journalEntryIdMeta = const VerificationMeta(
    'journalEntryId',
  );
  @override
  late final GeneratedColumn<String> journalEntryId = GeneratedColumn<String>(
    'journal_entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String> units =
      GeneratedColumn<String>(
        'units',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>($PostingsTable.$converterunits);
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal?, String> costPerUnit =
      GeneratedColumn<String>(
        'cost_per_unit',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Decimal?>($PostingsTable.$convertercostPerUnitn);
  static const VerificationMeta _costCurrencyMeta = const VerificationMeta(
    'costCurrency',
  );
  @override
  late final GeneratedColumn<String> costCurrency = GeneratedColumn<String>(
    'cost_currency',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _costLotIdMeta = const VerificationMeta(
    'costLotId',
  );
  @override
  late final GeneratedColumn<String> costLotId = GeneratedColumn<String>(
    'cost_lot_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _costAcquiredOnMeta = const VerificationMeta(
    'costAcquiredOn',
  );
  @override
  late final GeneratedColumn<DateTime> costAcquiredOn =
      GeneratedColumn<DateTime>(
        'cost_acquired_on',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal?, String> pricePerUnit =
      GeneratedColumn<String>(
        'price_per_unit',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Decimal?>($PostingsTable.$converterpricePerUnitn);
  static const VerificationMeta _priceCurrencyMeta = const VerificationMeta(
    'priceCurrency',
  );
  @override
  late final GeneratedColumn<String> priceCurrency = GeneratedColumn<String>(
    'price_currency',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    journalEntryId,
    position,
    accountId,
    units,
    unit,
    costPerUnit,
    costCurrency,
    costLotId,
    costAcquiredOn,
    pricePerUnit,
    priceCurrency,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'postings';
  @override
  VerificationContext validateIntegrity(
    Insertable<PostingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('journal_entry_id')) {
      context.handle(
        _journalEntryIdMeta,
        journalEntryId.isAcceptableOrUnknown(
          data['journal_entry_id']!,
          _journalEntryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_journalEntryIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('cost_currency')) {
      context.handle(
        _costCurrencyMeta,
        costCurrency.isAcceptableOrUnknown(
          data['cost_currency']!,
          _costCurrencyMeta,
        ),
      );
    }
    if (data.containsKey('cost_lot_id')) {
      context.handle(
        _costLotIdMeta,
        costLotId.isAcceptableOrUnknown(data['cost_lot_id']!, _costLotIdMeta),
      );
    }
    if (data.containsKey('cost_acquired_on')) {
      context.handle(
        _costAcquiredOnMeta,
        costAcquiredOn.isAcceptableOrUnknown(
          data['cost_acquired_on']!,
          _costAcquiredOnMeta,
        ),
      );
    }
    if (data.containsKey('price_currency')) {
      context.handle(
        _priceCurrencyMeta,
        priceCurrency.isAcceptableOrUnknown(
          data['price_currency']!,
          _priceCurrencyMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PostingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PostingRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $PostingsTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      journalEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journal_entry_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      units: $PostingsTable.$converterunits.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}units'],
        )!,
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      costPerUnit: $PostingsTable.$convertercostPerUnitn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}cost_per_unit'],
        ),
      ),
      costCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cost_currency'],
      ),
      costLotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cost_lot_id'],
      ),
      costAcquiredOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cost_acquired_on'],
      ),
      pricePerUnit: $PostingsTable.$converterpricePerUnitn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}price_per_unit'],
        ),
      ),
      priceCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}price_currency'],
      ),
    );
  }

  @override
  $PostingsTable createAlias(String alias) {
    return $PostingsTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<Decimal, String> $converterunits =
      const DecimalConverter();
  static TypeConverter<Decimal, String> $convertercostPerUnit =
      const DecimalConverter();
  static TypeConverter<Decimal?, String?> $convertercostPerUnitn =
      NullAwareTypeConverter.wrap($convertercostPerUnit);
  static TypeConverter<Decimal, String> $converterpricePerUnit =
      const DecimalConverter();
  static TypeConverter<Decimal?, String?> $converterpricePerUnitn =
      NullAwareTypeConverter.wrap($converterpricePerUnit);
}

class PostingRow extends DataClass implements Insertable<PostingRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String journalEntryId;

  /// 0-based render order within the parent JE. Stored explicitly so a
  /// re-order is a single-column LWW update rather than a JE-wide
  /// rewrite that touches every leg.
  final int position;
  final String accountId;

  /// Signed delta applied to the account's balance in [unit] terms.
  final Decimal units;

  /// Either an ISO 4217 currency code (`'CNY'`, `'USD'`) or an
  /// `assets.id` (`'us_stock:AAPL'`). The unit's namespace is
  /// disambiguated at read time by joining against `assets`.
  final String unit;
  final Decimal? costPerUnit;
  final String? costCurrency;
  final String? costLotId;
  final DateTime? costAcquiredOn;
  final Decimal? pricePerUnit;
  final String? priceCurrency;
  const PostingRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.journalEntryId,
    required this.position,
    required this.accountId,
    required this.units,
    required this.unit,
    this.costPerUnit,
    this.costCurrency,
    this.costLotId,
    this.costAcquiredOn,
    this.pricePerUnit,
    this.priceCurrency,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($PostingsTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['journal_entry_id'] = Variable<String>(journalEntryId);
    map['position'] = Variable<int>(position);
    map['account_id'] = Variable<String>(accountId);
    {
      map['units'] = Variable<String>(
        $PostingsTable.$converterunits.toSql(units),
      );
    }
    map['unit'] = Variable<String>(unit);
    if (!nullToAbsent || costPerUnit != null) {
      map['cost_per_unit'] = Variable<String>(
        $PostingsTable.$convertercostPerUnitn.toSql(costPerUnit),
      );
    }
    if (!nullToAbsent || costCurrency != null) {
      map['cost_currency'] = Variable<String>(costCurrency);
    }
    if (!nullToAbsent || costLotId != null) {
      map['cost_lot_id'] = Variable<String>(costLotId);
    }
    if (!nullToAbsent || costAcquiredOn != null) {
      map['cost_acquired_on'] = Variable<DateTime>(costAcquiredOn);
    }
    if (!nullToAbsent || pricePerUnit != null) {
      map['price_per_unit'] = Variable<String>(
        $PostingsTable.$converterpricePerUnitn.toSql(pricePerUnit),
      );
    }
    if (!nullToAbsent || priceCurrency != null) {
      map['price_currency'] = Variable<String>(priceCurrency);
    }
    return map;
  }

  PostingsCompanion toCompanion(bool nullToAbsent) {
    return PostingsCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      journalEntryId: Value(journalEntryId),
      position: Value(position),
      accountId: Value(accountId),
      units: Value(units),
      unit: Value(unit),
      costPerUnit: costPerUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(costPerUnit),
      costCurrency: costCurrency == null && nullToAbsent
          ? const Value.absent()
          : Value(costCurrency),
      costLotId: costLotId == null && nullToAbsent
          ? const Value.absent()
          : Value(costLotId),
      costAcquiredOn: costAcquiredOn == null && nullToAbsent
          ? const Value.absent()
          : Value(costAcquiredOn),
      pricePerUnit: pricePerUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(pricePerUnit),
      priceCurrency: priceCurrency == null && nullToAbsent
          ? const Value.absent()
          : Value(priceCurrency),
    );
  }

  factory PostingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PostingRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      journalEntryId: serializer.fromJson<String>(json['journalEntryId']),
      position: serializer.fromJson<int>(json['position']),
      accountId: serializer.fromJson<String>(json['accountId']),
      units: serializer.fromJson<Decimal>(json['units']),
      unit: serializer.fromJson<String>(json['unit']),
      costPerUnit: serializer.fromJson<Decimal?>(json['costPerUnit']),
      costCurrency: serializer.fromJson<String?>(json['costCurrency']),
      costLotId: serializer.fromJson<String?>(json['costLotId']),
      costAcquiredOn: serializer.fromJson<DateTime?>(json['costAcquiredOn']),
      pricePerUnit: serializer.fromJson<Decimal?>(json['pricePerUnit']),
      priceCurrency: serializer.fromJson<String?>(json['priceCurrency']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'journalEntryId': serializer.toJson<String>(journalEntryId),
      'position': serializer.toJson<int>(position),
      'accountId': serializer.toJson<String>(accountId),
      'units': serializer.toJson<Decimal>(units),
      'unit': serializer.toJson<String>(unit),
      'costPerUnit': serializer.toJson<Decimal?>(costPerUnit),
      'costCurrency': serializer.toJson<String?>(costCurrency),
      'costLotId': serializer.toJson<String?>(costLotId),
      'costAcquiredOn': serializer.toJson<DateTime?>(costAcquiredOn),
      'pricePerUnit': serializer.toJson<Decimal?>(pricePerUnit),
      'priceCurrency': serializer.toJson<String?>(priceCurrency),
    };
  }

  PostingRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? journalEntryId,
    int? position,
    String? accountId,
    Decimal? units,
    String? unit,
    Value<Decimal?> costPerUnit = const Value.absent(),
    Value<String?> costCurrency = const Value.absent(),
    Value<String?> costLotId = const Value.absent(),
    Value<DateTime?> costAcquiredOn = const Value.absent(),
    Value<Decimal?> pricePerUnit = const Value.absent(),
    Value<String?> priceCurrency = const Value.absent(),
  }) => PostingRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    journalEntryId: journalEntryId ?? this.journalEntryId,
    position: position ?? this.position,
    accountId: accountId ?? this.accountId,
    units: units ?? this.units,
    unit: unit ?? this.unit,
    costPerUnit: costPerUnit.present ? costPerUnit.value : this.costPerUnit,
    costCurrency: costCurrency.present ? costCurrency.value : this.costCurrency,
    costLotId: costLotId.present ? costLotId.value : this.costLotId,
    costAcquiredOn: costAcquiredOn.present
        ? costAcquiredOn.value
        : this.costAcquiredOn,
    pricePerUnit: pricePerUnit.present ? pricePerUnit.value : this.pricePerUnit,
    priceCurrency: priceCurrency.present
        ? priceCurrency.value
        : this.priceCurrency,
  );
  PostingRow copyWithCompanion(PostingsCompanion data) {
    return PostingRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      journalEntryId: data.journalEntryId.present
          ? data.journalEntryId.value
          : this.journalEntryId,
      position: data.position.present ? data.position.value : this.position,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      units: data.units.present ? data.units.value : this.units,
      unit: data.unit.present ? data.unit.value : this.unit,
      costPerUnit: data.costPerUnit.present
          ? data.costPerUnit.value
          : this.costPerUnit,
      costCurrency: data.costCurrency.present
          ? data.costCurrency.value
          : this.costCurrency,
      costLotId: data.costLotId.present ? data.costLotId.value : this.costLotId,
      costAcquiredOn: data.costAcquiredOn.present
          ? data.costAcquiredOn.value
          : this.costAcquiredOn,
      pricePerUnit: data.pricePerUnit.present
          ? data.pricePerUnit.value
          : this.pricePerUnit,
      priceCurrency: data.priceCurrency.present
          ? data.priceCurrency.value
          : this.priceCurrency,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PostingRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('journalEntryId: $journalEntryId, ')
          ..write('position: $position, ')
          ..write('accountId: $accountId, ')
          ..write('units: $units, ')
          ..write('unit: $unit, ')
          ..write('costPerUnit: $costPerUnit, ')
          ..write('costCurrency: $costCurrency, ')
          ..write('costLotId: $costLotId, ')
          ..write('costAcquiredOn: $costAcquiredOn, ')
          ..write('pricePerUnit: $pricePerUnit, ')
          ..write('priceCurrency: $priceCurrency')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    journalEntryId,
    position,
    accountId,
    units,
    unit,
    costPerUnit,
    costCurrency,
    costLotId,
    costAcquiredOn,
    pricePerUnit,
    priceCurrency,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PostingRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.journalEntryId == this.journalEntryId &&
          other.position == this.position &&
          other.accountId == this.accountId &&
          other.units == this.units &&
          other.unit == this.unit &&
          other.costPerUnit == this.costPerUnit &&
          other.costCurrency == this.costCurrency &&
          other.costLotId == this.costLotId &&
          other.costAcquiredOn == this.costAcquiredOn &&
          other.pricePerUnit == this.pricePerUnit &&
          other.priceCurrency == this.priceCurrency);
}

class PostingsCompanion extends UpdateCompanion<PostingRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> journalEntryId;
  final Value<int> position;
  final Value<String> accountId;
  final Value<Decimal> units;
  final Value<String> unit;
  final Value<Decimal?> costPerUnit;
  final Value<String?> costCurrency;
  final Value<String?> costLotId;
  final Value<DateTime?> costAcquiredOn;
  final Value<Decimal?> pricePerUnit;
  final Value<String?> priceCurrency;
  final Value<int> rowid;
  const PostingsCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.journalEntryId = const Value.absent(),
    this.position = const Value.absent(),
    this.accountId = const Value.absent(),
    this.units = const Value.absent(),
    this.unit = const Value.absent(),
    this.costPerUnit = const Value.absent(),
    this.costCurrency = const Value.absent(),
    this.costLotId = const Value.absent(),
    this.costAcquiredOn = const Value.absent(),
    this.pricePerUnit = const Value.absent(),
    this.priceCurrency = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PostingsCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String journalEntryId,
    required int position,
    required String accountId,
    required Decimal units,
    required String unit,
    this.costPerUnit = const Value.absent(),
    this.costCurrency = const Value.absent(),
    this.costLotId = const Value.absent(),
    this.costAcquiredOn = const Value.absent(),
    this.pricePerUnit = const Value.absent(),
    this.priceCurrency = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       journalEntryId = Value(journalEntryId),
       position = Value(position),
       accountId = Value(accountId),
       units = Value(units),
       unit = Value(unit);
  static Insertable<PostingRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? journalEntryId,
    Expression<int>? position,
    Expression<String>? accountId,
    Expression<String>? units,
    Expression<String>? unit,
    Expression<String>? costPerUnit,
    Expression<String>? costCurrency,
    Expression<String>? costLotId,
    Expression<DateTime>? costAcquiredOn,
    Expression<String>? pricePerUnit,
    Expression<String>? priceCurrency,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (journalEntryId != null) 'journal_entry_id': journalEntryId,
      if (position != null) 'position': position,
      if (accountId != null) 'account_id': accountId,
      if (units != null) 'units': units,
      if (unit != null) 'unit': unit,
      if (costPerUnit != null) 'cost_per_unit': costPerUnit,
      if (costCurrency != null) 'cost_currency': costCurrency,
      if (costLotId != null) 'cost_lot_id': costLotId,
      if (costAcquiredOn != null) 'cost_acquired_on': costAcquiredOn,
      if (pricePerUnit != null) 'price_per_unit': pricePerUnit,
      if (priceCurrency != null) 'price_currency': priceCurrency,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PostingsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? journalEntryId,
    Value<int>? position,
    Value<String>? accountId,
    Value<Decimal>? units,
    Value<String>? unit,
    Value<Decimal?>? costPerUnit,
    Value<String?>? costCurrency,
    Value<String?>? costLotId,
    Value<DateTime?>? costAcquiredOn,
    Value<Decimal?>? pricePerUnit,
    Value<String?>? priceCurrency,
    Value<int>? rowid,
  }) {
    return PostingsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      position: position ?? this.position,
      accountId: accountId ?? this.accountId,
      units: units ?? this.units,
      unit: unit ?? this.unit,
      costPerUnit: costPerUnit ?? this.costPerUnit,
      costCurrency: costCurrency ?? this.costCurrency,
      costLotId: costLotId ?? this.costLotId,
      costAcquiredOn: costAcquiredOn ?? this.costAcquiredOn,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      priceCurrency: priceCurrency ?? this.priceCurrency,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $PostingsTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (journalEntryId.present) {
      map['journal_entry_id'] = Variable<String>(journalEntryId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (units.present) {
      map['units'] = Variable<String>(
        $PostingsTable.$converterunits.toSql(units.value),
      );
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (costPerUnit.present) {
      map['cost_per_unit'] = Variable<String>(
        $PostingsTable.$convertercostPerUnitn.toSql(costPerUnit.value),
      );
    }
    if (costCurrency.present) {
      map['cost_currency'] = Variable<String>(costCurrency.value);
    }
    if (costLotId.present) {
      map['cost_lot_id'] = Variable<String>(costLotId.value);
    }
    if (costAcquiredOn.present) {
      map['cost_acquired_on'] = Variable<DateTime>(costAcquiredOn.value);
    }
    if (pricePerUnit.present) {
      map['price_per_unit'] = Variable<String>(
        $PostingsTable.$converterpricePerUnitn.toSql(pricePerUnit.value),
      );
    }
    if (priceCurrency.present) {
      map['price_currency'] = Variable<String>(priceCurrency.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PostingsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('journalEntryId: $journalEntryId, ')
          ..write('position: $position, ')
          ..write('accountId: $accountId, ')
          ..write('units: $units, ')
          ..write('unit: $unit, ')
          ..write('costPerUnit: $costPerUnit, ')
          ..write('costCurrency: $costCurrency, ')
          ..write('costLotId: $costLotId, ')
          ..write('costAcquiredOn: $costAcquiredOn, ')
          ..write('pricePerUnit: $pricePerUnit, ')
          ..write('priceCurrency: $priceCurrency, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PricesTable extends Prices with TableInfo<$PricesTable, PriceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PricesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceMeta = const VerificationMeta(
    'updatedByDevice',
  );
  @override
  late final GeneratedColumn<String> updatedByDevice = GeneratedColumn<String>(
    'updated_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Hlc, String> hlc =
      GeneratedColumn<String>(
        'hlc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Hlc>($PricesTable.$converterhlc);
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quoteCurrencyMeta = const VerificationMeta(
    'quoteCurrency',
  );
  @override
  late final GeneratedColumn<String> quoteCurrency = GeneratedColumn<String>(
    'quote_currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 8,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedOnMeta = const VerificationMeta(
    'observedOn',
  );
  @override
  late final GeneratedColumn<DateTime> observedOn = GeneratedColumn<DateTime>(
    'observed_on',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Decimal, String> perUnit =
      GeneratedColumn<String>(
        'per_unit',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Decimal>($PricesTable.$converterperUnit);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    unit,
    quoteCurrency,
    observedOn,
    perUnit,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prices';
  @override
  VerificationContext validateIntegrity(
    Insertable<PriceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device')) {
      context.handle(
        _updatedByDeviceMeta,
        updatedByDevice.isAcceptableOrUnknown(
          data['updated_by_device']!,
          _updatedByDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedByDeviceMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('quote_currency')) {
      context.handle(
        _quoteCurrencyMeta,
        quoteCurrency.isAcceptableOrUnknown(
          data['quote_currency']!,
          _quoteCurrencyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quoteCurrencyMeta);
    }
    if (data.containsKey('observed_on')) {
      context.handle(
        _observedOnMeta,
        observedOn.isAcceptableOrUnknown(data['observed_on']!, _observedOnMeta),
      );
    } else if (isInserting) {
      context.missing(_observedOnMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PriceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PriceRow(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device'],
      )!,
      hlc: $PricesTable.$converterhlc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}hlc'],
        )!,
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      quoteCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quote_currency'],
      )!,
      observedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}observed_on'],
      )!,
      perUnit: $PricesTable.$converterperUnit.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}per_unit'],
        )!,
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $PricesTable createAlias(String alias) {
    return $PricesTable(attachedDatabase, alias);
  }

  static TypeConverter<Hlc, String> $converterhlc = const HlcConverter();
  static TypeConverter<Decimal, String> $converterperUnit =
      const DecimalConverter();
}

class PriceRow extends DataClass implements Insertable<PriceRow> {
  /// Owner partition. Sync filters every read by the active user id, so
  /// even multi-account installs never leak rows across boundaries.
  final String ownerUserId;

  /// Server-authoritative wall time. The client writes this locally on
  /// creation; the server stomps it on push. It is the *displayable*
  /// "last modified" — never used for conflict resolution.
  final DateTime updatedAt;

  /// Last writer's device id. Drives the "edited from `<device>`" UI hint;
  /// also useful when debugging cross-device weirdness.
  final String updatedByDevice;

  /// Hybrid Logical Clock — the single source of truth for ordering and
  /// conflict resolution. See `domain/hlc.dart`.
  final Hlc hlc;

  /// Soft-delete tombstone. NULL means alive. Sync still ships deleted
  /// rows so peers learn about the delete; physical removal happens only
  /// during a separate `vacuum` pass.
  final DateTime? deletedAt;
  final String id;
  final String unit;
  final String quoteCurrency;
  final DateTime observedOn;
  final Decimal perUnit;
  final String source;
  const PriceRow({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
    required this.id,
    required this.unit,
    required this.quoteCurrency,
    required this.observedOn,
    required this.perUnit,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['updated_by_device'] = Variable<String>(updatedByDevice);
    {
      map['hlc'] = Variable<String>($PricesTable.$converterhlc.toSql(hlc));
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['id'] = Variable<String>(id);
    map['unit'] = Variable<String>(unit);
    map['quote_currency'] = Variable<String>(quoteCurrency);
    map['observed_on'] = Variable<DateTime>(observedOn);
    {
      map['per_unit'] = Variable<String>(
        $PricesTable.$converterperUnit.toSql(perUnit),
      );
    }
    map['source'] = Variable<String>(source);
    return map;
  }

  PricesCompanion toCompanion(bool nullToAbsent) {
    return PricesCompanion(
      ownerUserId: Value(ownerUserId),
      updatedAt: Value(updatedAt),
      updatedByDevice: Value(updatedByDevice),
      hlc: Value(hlc),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      id: Value(id),
      unit: Value(unit),
      quoteCurrency: Value(quoteCurrency),
      observedOn: Value(observedOn),
      perUnit: Value(perUnit),
      source: Value(source),
    );
  }

  factory PriceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PriceRow(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDevice: serializer.fromJson<String>(json['updatedByDevice']),
      hlc: serializer.fromJson<Hlc>(json['hlc']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      id: serializer.fromJson<String>(json['id']),
      unit: serializer.fromJson<String>(json['unit']),
      quoteCurrency: serializer.fromJson<String>(json['quoteCurrency']),
      observedOn: serializer.fromJson<DateTime>(json['observedOn']),
      perUnit: serializer.fromJson<Decimal>(json['perUnit']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDevice': serializer.toJson<String>(updatedByDevice),
      'hlc': serializer.toJson<Hlc>(hlc),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'id': serializer.toJson<String>(id),
      'unit': serializer.toJson<String>(unit),
      'quoteCurrency': serializer.toJson<String>(quoteCurrency),
      'observedOn': serializer.toJson<DateTime>(observedOn),
      'perUnit': serializer.toJson<Decimal>(perUnit),
      'source': serializer.toJson<String>(source),
    };
  }

  PriceRow copyWith({
    String? ownerUserId,
    DateTime? updatedAt,
    String? updatedByDevice,
    Hlc? hlc,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? id,
    String? unit,
    String? quoteCurrency,
    DateTime? observedOn,
    Decimal? perUnit,
    String? source,
  }) => PriceRow(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDevice: updatedByDevice ?? this.updatedByDevice,
    hlc: hlc ?? this.hlc,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    id: id ?? this.id,
    unit: unit ?? this.unit,
    quoteCurrency: quoteCurrency ?? this.quoteCurrency,
    observedOn: observedOn ?? this.observedOn,
    perUnit: perUnit ?? this.perUnit,
    source: source ?? this.source,
  );
  PriceRow copyWithCompanion(PricesCompanion data) {
    return PriceRow(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDevice: data.updatedByDevice.present
          ? data.updatedByDevice.value
          : this.updatedByDevice,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      id: data.id.present ? data.id.value : this.id,
      unit: data.unit.present ? data.unit.value : this.unit,
      quoteCurrency: data.quoteCurrency.present
          ? data.quoteCurrency.value
          : this.quoteCurrency,
      observedOn: data.observedOn.present
          ? data.observedOn.value
          : this.observedOn,
      perUnit: data.perUnit.present ? data.perUnit.value : this.perUnit,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PriceRow(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('unit: $unit, ')
          ..write('quoteCurrency: $quoteCurrency, ')
          ..write('observedOn: $observedOn, ')
          ..write('perUnit: $perUnit, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
    id,
    unit,
    quoteCurrency,
    observedOn,
    perUnit,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PriceRow &&
          other.ownerUserId == this.ownerUserId &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDevice == this.updatedByDevice &&
          other.hlc == this.hlc &&
          other.deletedAt == this.deletedAt &&
          other.id == this.id &&
          other.unit == this.unit &&
          other.quoteCurrency == this.quoteCurrency &&
          other.observedOn == this.observedOn &&
          other.perUnit == this.perUnit &&
          other.source == this.source);
}

class PricesCompanion extends UpdateCompanion<PriceRow> {
  final Value<String> ownerUserId;
  final Value<DateTime> updatedAt;
  final Value<String> updatedByDevice;
  final Value<Hlc> hlc;
  final Value<DateTime?> deletedAt;
  final Value<String> id;
  final Value<String> unit;
  final Value<String> quoteCurrency;
  final Value<DateTime> observedOn;
  final Value<Decimal> perUnit;
  final Value<String> source;
  final Value<int> rowid;
  const PricesCompanion({
    this.ownerUserId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDevice = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.unit = const Value.absent(),
    this.quoteCurrency = const Value.absent(),
    this.observedOn = const Value.absent(),
    this.perUnit = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PricesCompanion.insert({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    this.deletedAt = const Value.absent(),
    required String id,
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
    required Decimal perUnit,
    required String source,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       updatedAt = Value(updatedAt),
       updatedByDevice = Value(updatedByDevice),
       hlc = Value(hlc),
       id = Value(id),
       unit = Value(unit),
       quoteCurrency = Value(quoteCurrency),
       observedOn = Value(observedOn),
       perUnit = Value(perUnit),
       source = Value(source);
  static Insertable<PriceRow> custom({
    Expression<String>? ownerUserId,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDevice,
    Expression<String>? hlc,
    Expression<DateTime>? deletedAt,
    Expression<String>? id,
    Expression<String>? unit,
    Expression<String>? quoteCurrency,
    Expression<DateTime>? observedOn,
    Expression<String>? perUnit,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDevice != null) 'updated_by_device': updatedByDevice,
      if (hlc != null) 'hlc': hlc,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (id != null) 'id': id,
      if (unit != null) 'unit': unit,
      if (quoteCurrency != null) 'quote_currency': quoteCurrency,
      if (observedOn != null) 'observed_on': observedOn,
      if (perUnit != null) 'per_unit': perUnit,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PricesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<DateTime>? updatedAt,
    Value<String>? updatedByDevice,
    Value<Hlc>? hlc,
    Value<DateTime?>? deletedAt,
    Value<String>? id,
    Value<String>? unit,
    Value<String>? quoteCurrency,
    Value<DateTime>? observedOn,
    Value<Decimal>? perUnit,
    Value<String>? source,
    Value<int>? rowid,
  }) {
    return PricesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDevice: updatedByDevice ?? this.updatedByDevice,
      hlc: hlc ?? this.hlc,
      deletedAt: deletedAt ?? this.deletedAt,
      id: id ?? this.id,
      unit: unit ?? this.unit,
      quoteCurrency: quoteCurrency ?? this.quoteCurrency,
      observedOn: observedOn ?? this.observedOn,
      perUnit: perUnit ?? this.perUnit,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDevice.present) {
      map['updated_by_device'] = Variable<String>(updatedByDevice.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(
        $PricesTable.$converterhlc.toSql(hlc.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (quoteCurrency.present) {
      map['quote_currency'] = Variable<String>(quoteCurrency.value);
    }
    if (observedOn.present) {
      map['observed_on'] = Variable<DateTime>(observedOn.value);
    }
    if (perUnit.present) {
      map['per_unit'] = Variable<String>(
        $PricesTable.$converterperUnit.toSql(perUnit.value),
      );
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PricesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDevice: $updatedByDevice, ')
          ..write('hlc: $hlc, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('id: $id, ')
          ..write('unit: $unit, ')
          ..write('quoteCurrency: $quoteCurrency, ')
          ..write('observedOn: $observedOn, ')
          ..write('perUnit: $perUnit, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTable users = $UsersTable(this);
  late final $SettingsTableTable settingsTable = $SettingsTableTable(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $AssetsTable assets = $AssetsTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $LiabilitiesTable liabilities = $LiabilitiesTable(this);
  late final $AmortizationEntriesTable amortizationEntries =
      $AmortizationEntriesTable(this);
  late final $CurrenciesTable currencies = $CurrenciesTable(this);
  late final $FxRatesTable fxRates = $FxRatesTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $TagLinksTable tagLinks = $TagLinksTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ExpenseCategoriesTable expenseCategories =
      $ExpenseCategoriesTable(this);
  late final $GoalsTable goals = $GoalsTable(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $OpLogsTable opLogs = $OpLogsTable(this);
  late final $MarketQuotesTable marketQuotes = $MarketQuotesTable(this);
  late final $MarketHistoryBarsTable marketHistoryBars =
      $MarketHistoryBarsTable(this);
  late final $MarketSymbolSearchesTable marketSymbolSearches =
      $MarketSymbolSearchesTable(this);
  late final $SecuritiesCatalogTable securitiesCatalog =
      $SecuritiesCatalogTable(this);
  late final $SecuritiesCatalogMetaTable securitiesCatalogMeta =
      $SecuritiesCatalogMetaTable(this);
  late final $JournalEntriesTable journalEntries = $JournalEntriesTable(this);
  late final $PostingsTable postings = $PostingsTable(this);
  late final $PricesTable prices = $PricesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    users,
    settingsTable,
    accounts,
    assets,
    transactions,
    liabilities,
    amortizationEntries,
    currencies,
    fxRates,
    tags,
    tagLinks,
    categories,
    expenseCategories,
    goals,
    devices,
    opLogs,
    marketQuotes,
    marketHistoryBars,
    marketSymbolSearches,
    securitiesCatalog,
    securitiesCatalogMeta,
    journalEntries,
    postings,
    prices,
  ];
}

typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String name,
      Value<String?> email,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> name,
      Value<String?> email,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          UserRow,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (UserRow, BaseReferences<_$AppDatabase, $UsersTable, UserRow>),
          UserRow,
          PrefetchHooks Function()
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                email: email,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String name,
                Value<String?> email = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                email: email,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      UserRow,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (UserRow, BaseReferences<_$AppDatabase, $UsersTable, UserRow>),
      UserRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableTableCreateCompanionBuilder =
    SettingsTableCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String userId,
      required String baseCurrency,
      required AppThemeMode themeMode,
      required PrivacyMode privacyMode,
      required CostBasisMethod costBasisMethod,
      Value<int> rowid,
    });
typedef $$SettingsTableTableUpdateCompanionBuilder =
    SettingsTableCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> userId,
      Value<String> baseCurrency,
      Value<AppThemeMode> themeMode,
      Value<PrivacyMode> privacyMode,
      Value<CostBasisMethod> costBasisMethod,
      Value<int> rowid,
    });

class $$SettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AppThemeMode, AppThemeMode, String>
  get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<PrivacyMode, PrivacyMode, String>
  get privacyMode => $composableBuilder(
    column: $table.privacyMode,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<CostBasisMethod, CostBasisMethod, String>
  get costBasisMethod => $composableBuilder(
    column: $table.costBasisMethod,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$SettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get privacyMode => $composableBuilder(
    column: $table.privacyMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get costBasisMethod => $composableBuilder(
    column: $table.costBasisMethod,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<AppThemeMode, String> get themeMode =>
      $composableBuilder(column: $table.themeMode, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PrivacyMode, String> get privacyMode =>
      $composableBuilder(
        column: $table.privacyMode,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<CostBasisMethod, String>
  get costBasisMethod => $composableBuilder(
    column: $table.costBasisMethod,
    builder: (column) => column,
  );
}

class $$SettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTableTable,
          SettingsRow,
          $$SettingsTableTableFilterComposer,
          $$SettingsTableTableOrderingComposer,
          $$SettingsTableTableAnnotationComposer,
          $$SettingsTableTableCreateCompanionBuilder,
          $$SettingsTableTableUpdateCompanionBuilder,
          (
            SettingsRow,
            BaseReferences<_$AppDatabase, $SettingsTableTable, SettingsRow>,
          ),
          SettingsRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableTableManager(_$AppDatabase db, $SettingsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> baseCurrency = const Value.absent(),
                Value<AppThemeMode> themeMode = const Value.absent(),
                Value<PrivacyMode> privacyMode = const Value.absent(),
                Value<CostBasisMethod> costBasisMethod = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsTableCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                userId: userId,
                baseCurrency: baseCurrency,
                themeMode: themeMode,
                privacyMode: privacyMode,
                costBasisMethod: costBasisMethod,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String userId,
                required String baseCurrency,
                required AppThemeMode themeMode,
                required PrivacyMode privacyMode,
                required CostBasisMethod costBasisMethod,
                Value<int> rowid = const Value.absent(),
              }) => SettingsTableCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                userId: userId,
                baseCurrency: baseCurrency,
                themeMode: themeMode,
                privacyMode: privacyMode,
                costBasisMethod: costBasisMethod,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTableTable,
      SettingsRow,
      $$SettingsTableTableFilterComposer,
      $$SettingsTableTableOrderingComposer,
      $$SettingsTableTableAnnotationComposer,
      $$SettingsTableTableCreateCompanionBuilder,
      $$SettingsTableTableUpdateCompanionBuilder,
      (
        SettingsRow,
        BaseReferences<_$AppDatabase, $SettingsTableTable, SettingsRow>,
      ),
      SettingsRow,
      PrefetchHooks Function()
    >;
typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required AccountType type,
      required String name,
      required String currency,
      Value<String?> institution,
      Value<String?> accountNumber,
      Value<String?> note,
      Value<bool> archived,
      Value<AccountCategory> category,
      Value<String?> parentId,
      Value<String?> icon,
      Value<String?> color,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<AccountType> type,
      Value<String> name,
      Value<String> currency,
      Value<String?> institution,
      Value<String?> accountNumber,
      Value<String?> note,
      Value<bool> archived,
      Value<AccountCategory> category,
      Value<String?> parentId,
      Value<String?> icon,
      Value<String?> color,
      Value<int> rowid,
    });

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AccountType, AccountType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get institution => $composableBuilder(
    column: $table.institution,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountNumber => $composableBuilder(
    column: $table.accountNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AccountCategory, AccountCategory, String>
  get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get institution => $composableBuilder(
    column: $table.institution,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountNumber => $composableBuilder(
    column: $table.accountNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AccountType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get institution => $composableBuilder(
    column: $table.institution,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountNumber => $composableBuilder(
    column: $table.accountNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AccountCategory, String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          AccountRow,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (
            AccountRow,
            BaseReferences<_$AppDatabase, $AccountsTable, AccountRow>,
          ),
          AccountRow,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<AccountType> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String?> institution = const Value.absent(),
                Value<String?> accountNumber = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<AccountCategory> category = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                type: type,
                name: name,
                currency: currency,
                institution: institution,
                accountNumber: accountNumber,
                note: note,
                archived: archived,
                category: category,
                parentId: parentId,
                icon: icon,
                color: color,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required AccountType type,
                required String name,
                required String currency,
                Value<String?> institution = const Value.absent(),
                Value<String?> accountNumber = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<AccountCategory> category = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                type: type,
                name: name,
                currency: currency,
                institution: institution,
                accountNumber: accountNumber,
                note: note,
                archived: archived,
                category: category,
                parentId: parentId,
                icon: icon,
                color: color,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      AccountRow,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (AccountRow, BaseReferences<_$AppDatabase, $AccountsTable, AccountRow>),
      AccountRow,
      PrefetchHooks Function()
    >;
typedef $$AssetsTableCreateCompanionBuilder =
    AssetsCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required AssetType type,
      required String symbol,
      required String currency,
      Value<String?> name,
      Value<String?> market,
      Value<String?> industry,
      Value<String?> region,
      Value<String?> isin,
      Value<Decimal?> lastPrice,
      Value<DateTime?> lastPriceAt,
      Value<String?> logoUrl,
      Value<String?> metadataJson,
      Value<int> rowid,
    });
typedef $$AssetsTableUpdateCompanionBuilder =
    AssetsCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<AssetType> type,
      Value<String> symbol,
      Value<String> currency,
      Value<String?> name,
      Value<String?> market,
      Value<String?> industry,
      Value<String?> region,
      Value<String?> isin,
      Value<Decimal?> lastPrice,
      Value<DateTime?> lastPriceAt,
      Value<String?> logoUrl,
      Value<String?> metadataJson,
      Value<int> rowid,
    });

class $$AssetsTableFilterComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AssetType, AssetType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get market => $composableBuilder(
    column: $table.market,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get industry => $composableBuilder(
    column: $table.industry,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isin => $composableBuilder(
    column: $table.isin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal?, Decimal, String> get lastPrice =>
      $composableBuilder(
        column: $table.lastPrice,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get lastPriceAt => $composableBuilder(
    column: $table.lastPriceAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get market => $composableBuilder(
    column: $table.market,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get industry => $composableBuilder(
    column: $table.industry,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isin => $composableBuilder(
    column: $table.isin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPrice => $composableBuilder(
    column: $table.lastPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPriceAt => $composableBuilder(
    column: $table.lastPriceAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AssetType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get market =>
      $composableBuilder(column: $table.market, builder: (column) => column);

  GeneratedColumn<String> get industry =>
      $composableBuilder(column: $table.industry, builder: (column) => column);

  GeneratedColumn<String> get region =>
      $composableBuilder(column: $table.region, builder: (column) => column);

  GeneratedColumn<String> get isin =>
      $composableBuilder(column: $table.isin, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal?, String> get lastPrice =>
      $composableBuilder(column: $table.lastPrice, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPriceAt => $composableBuilder(
    column: $table.lastPriceAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get logoUrl =>
      $composableBuilder(column: $table.logoUrl, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );
}

class $$AssetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssetsTable,
          AssetRow,
          $$AssetsTableFilterComposer,
          $$AssetsTableOrderingComposer,
          $$AssetsTableAnnotationComposer,
          $$AssetsTableCreateCompanionBuilder,
          $$AssetsTableUpdateCompanionBuilder,
          (AssetRow, BaseReferences<_$AppDatabase, $AssetsTable, AssetRow>),
          AssetRow,
          PrefetchHooks Function()
        > {
  $$AssetsTableTableManager(_$AppDatabase db, $AssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<AssetType> type = const Value.absent(),
                Value<String> symbol = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> market = const Value.absent(),
                Value<String?> industry = const Value.absent(),
                Value<String?> region = const Value.absent(),
                Value<String?> isin = const Value.absent(),
                Value<Decimal?> lastPrice = const Value.absent(),
                Value<DateTime?> lastPriceAt = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                type: type,
                symbol: symbol,
                currency: currency,
                name: name,
                market: market,
                industry: industry,
                region: region,
                isin: isin,
                lastPrice: lastPrice,
                lastPriceAt: lastPriceAt,
                logoUrl: logoUrl,
                metadataJson: metadataJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required AssetType type,
                required String symbol,
                required String currency,
                Value<String?> name = const Value.absent(),
                Value<String?> market = const Value.absent(),
                Value<String?> industry = const Value.absent(),
                Value<String?> region = const Value.absent(),
                Value<String?> isin = const Value.absent(),
                Value<Decimal?> lastPrice = const Value.absent(),
                Value<DateTime?> lastPriceAt = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                type: type,
                symbol: symbol,
                currency: currency,
                name: name,
                market: market,
                industry: industry,
                region: region,
                isin: isin,
                lastPrice: lastPrice,
                lastPriceAt: lastPriceAt,
                logoUrl: logoUrl,
                metadataJson: metadataJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssetsTable,
      AssetRow,
      $$AssetsTableFilterComposer,
      $$AssetsTableOrderingComposer,
      $$AssetsTableAnnotationComposer,
      $$AssetsTableCreateCompanionBuilder,
      $$AssetsTableUpdateCompanionBuilder,
      (AssetRow, BaseReferences<_$AppDatabase, $AssetsTable, AssetRow>),
      AssetRow,
      PrefetchHooks Function()
    >;
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String accountId,
      Value<String?> assetId,
      required TransactionType type,
      required Decimal quantity,
      required Decimal price,
      required String currency,
      required DateTime tradeDate,
      Value<DateTime?> settleDate,
      Value<Decimal?> fee,
      Value<Decimal?> tax,
      Value<String?> counterAccountId,
      Value<String?> lotId,
      Value<String?> note,
      Value<String?> expenseMetadataJson,
      Value<String?> transferGroupId,
      Value<int> rowid,
    });
typedef $$TransactionsTableUpdateCompanionBuilder =
    TransactionsCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> accountId,
      Value<String?> assetId,
      Value<TransactionType> type,
      Value<Decimal> quantity,
      Value<Decimal> price,
      Value<String> currency,
      Value<DateTime> tradeDate,
      Value<DateTime?> settleDate,
      Value<Decimal?> fee,
      Value<Decimal?> tax,
      Value<String?> counterAccountId,
      Value<String?> lotId,
      Value<String?> note,
      Value<String?> expenseMetadataJson,
      Value<String?> transferGroupId,
      Value<int> rowid,
    });

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TransactionType, TransactionType, String>
  get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String> get quantity =>
      $composableBuilder(
        column: $table.quantity,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String> get price =>
      $composableBuilder(
        column: $table.price,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get tradeDate => $composableBuilder(
    column: $table.tradeDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get settleDate => $composableBuilder(
    column: $table.settleDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal?, Decimal, String> get fee =>
      $composableBuilder(
        column: $table.fee,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<Decimal?, Decimal, String> get tax =>
      $composableBuilder(
        column: $table.tax,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get counterAccountId => $composableBuilder(
    column: $table.counterAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lotId => $composableBuilder(
    column: $table.lotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expenseMetadataJson => $composableBuilder(
    column: $table.expenseMetadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferGroupId => $composableBuilder(
    column: $table.transferGroupId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get tradeDate => $composableBuilder(
    column: $table.tradeDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get settleDate => $composableBuilder(
    column: $table.settleDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fee => $composableBuilder(
    column: $table.fee,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tax => $composableBuilder(
    column: $table.tax,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get counterAccountId => $composableBuilder(
    column: $table.counterAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lotId => $composableBuilder(
    column: $table.lotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expenseMetadataJson => $composableBuilder(
    column: $table.expenseMetadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferGroupId => $composableBuilder(
    column: $table.transferGroupId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TransactionType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal, String> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal, String> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<DateTime> get tradeDate =>
      $composableBuilder(column: $table.tradeDate, builder: (column) => column);

  GeneratedColumn<DateTime> get settleDate => $composableBuilder(
    column: $table.settleDate,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Decimal?, String> get fee =>
      $composableBuilder(column: $table.fee, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal?, String> get tax =>
      $composableBuilder(column: $table.tax, builder: (column) => column);

  GeneratedColumn<String> get counterAccountId => $composableBuilder(
    column: $table.counterAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lotId =>
      $composableBuilder(column: $table.lotId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get expenseMetadataJson => $composableBuilder(
    column: $table.expenseMetadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transferGroupId => $composableBuilder(
    column: $table.transferGroupId,
    builder: (column) => column,
  );
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionsTable,
          TransactionRow,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (
            TransactionRow,
            BaseReferences<_$AppDatabase, $TransactionsTable, TransactionRow>,
          ),
          TransactionRow,
          PrefetchHooks Function()
        > {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String?> assetId = const Value.absent(),
                Value<TransactionType> type = const Value.absent(),
                Value<Decimal> quantity = const Value.absent(),
                Value<Decimal> price = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<DateTime> tradeDate = const Value.absent(),
                Value<DateTime?> settleDate = const Value.absent(),
                Value<Decimal?> fee = const Value.absent(),
                Value<Decimal?> tax = const Value.absent(),
                Value<String?> counterAccountId = const Value.absent(),
                Value<String?> lotId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> expenseMetadataJson = const Value.absent(),
                Value<String?> transferGroupId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                accountId: accountId,
                assetId: assetId,
                type: type,
                quantity: quantity,
                price: price,
                currency: currency,
                tradeDate: tradeDate,
                settleDate: settleDate,
                fee: fee,
                tax: tax,
                counterAccountId: counterAccountId,
                lotId: lotId,
                note: note,
                expenseMetadataJson: expenseMetadataJson,
                transferGroupId: transferGroupId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String accountId,
                Value<String?> assetId = const Value.absent(),
                required TransactionType type,
                required Decimal quantity,
                required Decimal price,
                required String currency,
                required DateTime tradeDate,
                Value<DateTime?> settleDate = const Value.absent(),
                Value<Decimal?> fee = const Value.absent(),
                Value<Decimal?> tax = const Value.absent(),
                Value<String?> counterAccountId = const Value.absent(),
                Value<String?> lotId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> expenseMetadataJson = const Value.absent(),
                Value<String?> transferGroupId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                accountId: accountId,
                assetId: assetId,
                type: type,
                quantity: quantity,
                price: price,
                currency: currency,
                tradeDate: tradeDate,
                settleDate: settleDate,
                fee: fee,
                tax: tax,
                counterAccountId: counterAccountId,
                lotId: lotId,
                note: note,
                expenseMetadataJson: expenseMetadataJson,
                transferGroupId: transferGroupId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionsTable,
      TransactionRow,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (
        TransactionRow,
        BaseReferences<_$AppDatabase, $TransactionsTable, TransactionRow>,
      ),
      TransactionRow,
      PrefetchHooks Function()
    >;
typedef $$LiabilitiesTableCreateCompanionBuilder =
    LiabilitiesCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required LiabilityType type,
      required String name,
      required Decimal principal,
      required Decimal interestRate,
      required String currency,
      Value<RepaymentMethod> paymentMethod,
      Value<LiabilityRateType> rateType,
      Value<String?> accountId,
      Value<DateTime?> startDate,
      Value<DateTime?> endDate,
      Value<int?> termMonths,
      Value<Decimal?> monthlyPayment,
      Value<int?> statementDay,
      Value<int?> paymentDueDay,
      Value<String?> note,
      Value<int> rowid,
    });
typedef $$LiabilitiesTableUpdateCompanionBuilder =
    LiabilitiesCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<LiabilityType> type,
      Value<String> name,
      Value<Decimal> principal,
      Value<Decimal> interestRate,
      Value<String> currency,
      Value<RepaymentMethod> paymentMethod,
      Value<LiabilityRateType> rateType,
      Value<String?> accountId,
      Value<DateTime?> startDate,
      Value<DateTime?> endDate,
      Value<int?> termMonths,
      Value<Decimal?> monthlyPayment,
      Value<int?> statementDay,
      Value<int?> paymentDueDay,
      Value<String?> note,
      Value<int> rowid,
    });

class $$LiabilitiesTableFilterComposer
    extends Composer<_$AppDatabase, $LiabilitiesTable> {
  $$LiabilitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LiabilityType, LiabilityType, String>
  get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String> get principal =>
      $composableBuilder(
        column: $table.principal,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String> get interestRate =>
      $composableBuilder(
        column: $table.interestRate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RepaymentMethod, RepaymentMethod, String>
  get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<LiabilityRateType, LiabilityRateType, String>
  get rateType => $composableBuilder(
    column: $table.rateType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get termMonths => $composableBuilder(
    column: $table.termMonths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal?, Decimal, String>
  get monthlyPayment => $composableBuilder(
    column: $table.monthlyPayment,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get statementDay => $composableBuilder(
    column: $table.statementDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paymentDueDay => $composableBuilder(
    column: $table.paymentDueDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LiabilitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $LiabilitiesTable> {
  $$LiabilitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get principal => $composableBuilder(
    column: $table.principal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get interestRate => $composableBuilder(
    column: $table.interestRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rateType => $composableBuilder(
    column: $table.rateType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get termMonths => $composableBuilder(
    column: $table.termMonths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get monthlyPayment => $composableBuilder(
    column: $table.monthlyPayment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get statementDay => $composableBuilder(
    column: $table.statementDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paymentDueDay => $composableBuilder(
    column: $table.paymentDueDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LiabilitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LiabilitiesTable> {
  $$LiabilitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LiabilityType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal, String> get principal =>
      $composableBuilder(column: $table.principal, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal, String> get interestRate =>
      $composableBuilder(
        column: $table.interestRate,
        builder: (column) => column,
      );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RepaymentMethod, String> get paymentMethod =>
      $composableBuilder(
        column: $table.paymentMethod,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<LiabilityRateType, String> get rateType =>
      $composableBuilder(column: $table.rateType, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<int> get termMonths => $composableBuilder(
    column: $table.termMonths,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Decimal?, String> get monthlyPayment =>
      $composableBuilder(
        column: $table.monthlyPayment,
        builder: (column) => column,
      );

  GeneratedColumn<int> get statementDay => $composableBuilder(
    column: $table.statementDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get paymentDueDay => $composableBuilder(
    column: $table.paymentDueDay,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$LiabilitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LiabilitiesTable,
          LiabilityRow,
          $$LiabilitiesTableFilterComposer,
          $$LiabilitiesTableOrderingComposer,
          $$LiabilitiesTableAnnotationComposer,
          $$LiabilitiesTableCreateCompanionBuilder,
          $$LiabilitiesTableUpdateCompanionBuilder,
          (
            LiabilityRow,
            BaseReferences<_$AppDatabase, $LiabilitiesTable, LiabilityRow>,
          ),
          LiabilityRow,
          PrefetchHooks Function()
        > {
  $$LiabilitiesTableTableManager(_$AppDatabase db, $LiabilitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LiabilitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LiabilitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LiabilitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<LiabilityType> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<Decimal> principal = const Value.absent(),
                Value<Decimal> interestRate = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<RepaymentMethod> paymentMethod = const Value.absent(),
                Value<LiabilityRateType> rateType = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<int?> termMonths = const Value.absent(),
                Value<Decimal?> monthlyPayment = const Value.absent(),
                Value<int?> statementDay = const Value.absent(),
                Value<int?> paymentDueDay = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LiabilitiesCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                type: type,
                name: name,
                principal: principal,
                interestRate: interestRate,
                currency: currency,
                paymentMethod: paymentMethod,
                rateType: rateType,
                accountId: accountId,
                startDate: startDate,
                endDate: endDate,
                termMonths: termMonths,
                monthlyPayment: monthlyPayment,
                statementDay: statementDay,
                paymentDueDay: paymentDueDay,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required LiabilityType type,
                required String name,
                required Decimal principal,
                required Decimal interestRate,
                required String currency,
                Value<RepaymentMethod> paymentMethod = const Value.absent(),
                Value<LiabilityRateType> rateType = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<int?> termMonths = const Value.absent(),
                Value<Decimal?> monthlyPayment = const Value.absent(),
                Value<int?> statementDay = const Value.absent(),
                Value<int?> paymentDueDay = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LiabilitiesCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                type: type,
                name: name,
                principal: principal,
                interestRate: interestRate,
                currency: currency,
                paymentMethod: paymentMethod,
                rateType: rateType,
                accountId: accountId,
                startDate: startDate,
                endDate: endDate,
                termMonths: termMonths,
                monthlyPayment: monthlyPayment,
                statementDay: statementDay,
                paymentDueDay: paymentDueDay,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LiabilitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LiabilitiesTable,
      LiabilityRow,
      $$LiabilitiesTableFilterComposer,
      $$LiabilitiesTableOrderingComposer,
      $$LiabilitiesTableAnnotationComposer,
      $$LiabilitiesTableCreateCompanionBuilder,
      $$LiabilitiesTableUpdateCompanionBuilder,
      (
        LiabilityRow,
        BaseReferences<_$AppDatabase, $LiabilitiesTable, LiabilityRow>,
      ),
      LiabilityRow,
      PrefetchHooks Function()
    >;
typedef $$AmortizationEntriesTableCreateCompanionBuilder =
    AmortizationEntriesCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String liabilityId,
      required int periodIndex,
      required DateTime dueDate,
      required Decimal principalPayment,
      required Decimal interestPayment,
      required Decimal remainingBalance,
      Value<DateTime?> paidAt,
      Value<int> rowid,
    });
typedef $$AmortizationEntriesTableUpdateCompanionBuilder =
    AmortizationEntriesCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> liabilityId,
      Value<int> periodIndex,
      Value<DateTime> dueDate,
      Value<Decimal> principalPayment,
      Value<Decimal> interestPayment,
      Value<Decimal> remainingBalance,
      Value<DateTime?> paidAt,
      Value<int> rowid,
    });

class $$AmortizationEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $AmortizationEntriesTable> {
  $$AmortizationEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get liabilityId => $composableBuilder(
    column: $table.liabilityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get periodIndex => $composableBuilder(
    column: $table.periodIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String>
  get principalPayment => $composableBuilder(
    column: $table.principalPayment,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String>
  get interestPayment => $composableBuilder(
    column: $table.interestPayment,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String>
  get remainingBalance => $composableBuilder(
    column: $table.remainingBalance,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get paidAt => $composableBuilder(
    column: $table.paidAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AmortizationEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $AmortizationEntriesTable> {
  $$AmortizationEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get liabilityId => $composableBuilder(
    column: $table.liabilityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get periodIndex => $composableBuilder(
    column: $table.periodIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get principalPayment => $composableBuilder(
    column: $table.principalPayment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get interestPayment => $composableBuilder(
    column: $table.interestPayment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remainingBalance => $composableBuilder(
    column: $table.remainingBalance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paidAt => $composableBuilder(
    column: $table.paidAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AmortizationEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AmortizationEntriesTable> {
  $$AmortizationEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get liabilityId => $composableBuilder(
    column: $table.liabilityId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get periodIndex => $composableBuilder(
    column: $table.periodIndex,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal, String> get principalPayment =>
      $composableBuilder(
        column: $table.principalPayment,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<Decimal, String> get interestPayment =>
      $composableBuilder(
        column: $table.interestPayment,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<Decimal, String> get remainingBalance =>
      $composableBuilder(
        column: $table.remainingBalance,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get paidAt =>
      $composableBuilder(column: $table.paidAt, builder: (column) => column);
}

class $$AmortizationEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AmortizationEntriesTable,
          AmortizationEntryRow,
          $$AmortizationEntriesTableFilterComposer,
          $$AmortizationEntriesTableOrderingComposer,
          $$AmortizationEntriesTableAnnotationComposer,
          $$AmortizationEntriesTableCreateCompanionBuilder,
          $$AmortizationEntriesTableUpdateCompanionBuilder,
          (
            AmortizationEntryRow,
            BaseReferences<
              _$AppDatabase,
              $AmortizationEntriesTable,
              AmortizationEntryRow
            >,
          ),
          AmortizationEntryRow,
          PrefetchHooks Function()
        > {
  $$AmortizationEntriesTableTableManager(
    _$AppDatabase db,
    $AmortizationEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AmortizationEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AmortizationEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AmortizationEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> liabilityId = const Value.absent(),
                Value<int> periodIndex = const Value.absent(),
                Value<DateTime> dueDate = const Value.absent(),
                Value<Decimal> principalPayment = const Value.absent(),
                Value<Decimal> interestPayment = const Value.absent(),
                Value<Decimal> remainingBalance = const Value.absent(),
                Value<DateTime?> paidAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AmortizationEntriesCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                liabilityId: liabilityId,
                periodIndex: periodIndex,
                dueDate: dueDate,
                principalPayment: principalPayment,
                interestPayment: interestPayment,
                remainingBalance: remainingBalance,
                paidAt: paidAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String liabilityId,
                required int periodIndex,
                required DateTime dueDate,
                required Decimal principalPayment,
                required Decimal interestPayment,
                required Decimal remainingBalance,
                Value<DateTime?> paidAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AmortizationEntriesCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                liabilityId: liabilityId,
                periodIndex: periodIndex,
                dueDate: dueDate,
                principalPayment: principalPayment,
                interestPayment: interestPayment,
                remainingBalance: remainingBalance,
                paidAt: paidAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AmortizationEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AmortizationEntriesTable,
      AmortizationEntryRow,
      $$AmortizationEntriesTableFilterComposer,
      $$AmortizationEntriesTableOrderingComposer,
      $$AmortizationEntriesTableAnnotationComposer,
      $$AmortizationEntriesTableCreateCompanionBuilder,
      $$AmortizationEntriesTableUpdateCompanionBuilder,
      (
        AmortizationEntryRow,
        BaseReferences<
          _$AppDatabase,
          $AmortizationEntriesTable,
          AmortizationEntryRow
        >,
      ),
      AmortizationEntryRow,
      PrefetchHooks Function()
    >;
typedef $$CurrenciesTableCreateCompanionBuilder =
    CurrenciesCompanion Function({
      required String code,
      required String name,
      required int decimals,
      Value<String?> symbol,
      Value<int> rowid,
    });
typedef $$CurrenciesTableUpdateCompanionBuilder =
    CurrenciesCompanion Function({
      Value<String> code,
      Value<String> name,
      Value<int> decimals,
      Value<String?> symbol,
      Value<int> rowid,
    });

class $$CurrenciesTableFilterComposer
    extends Composer<_$AppDatabase, $CurrenciesTable> {
  $$CurrenciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get decimals => $composableBuilder(
    column: $table.decimals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CurrenciesTableOrderingComposer
    extends Composer<_$AppDatabase, $CurrenciesTable> {
  $$CurrenciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decimals => $composableBuilder(
    column: $table.decimals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CurrenciesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CurrenciesTable> {
  $$CurrenciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get decimals =>
      $composableBuilder(column: $table.decimals, builder: (column) => column);

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);
}

class $$CurrenciesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CurrenciesTable,
          CurrencyRow,
          $$CurrenciesTableFilterComposer,
          $$CurrenciesTableOrderingComposer,
          $$CurrenciesTableAnnotationComposer,
          $$CurrenciesTableCreateCompanionBuilder,
          $$CurrenciesTableUpdateCompanionBuilder,
          (
            CurrencyRow,
            BaseReferences<_$AppDatabase, $CurrenciesTable, CurrencyRow>,
          ),
          CurrencyRow,
          PrefetchHooks Function()
        > {
  $$CurrenciesTableTableManager(_$AppDatabase db, $CurrenciesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CurrenciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CurrenciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CurrenciesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> decimals = const Value.absent(),
                Value<String?> symbol = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CurrenciesCompanion(
                code: code,
                name: name,
                decimals: decimals,
                symbol: symbol,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String code,
                required String name,
                required int decimals,
                Value<String?> symbol = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CurrenciesCompanion.insert(
                code: code,
                name: name,
                decimals: decimals,
                symbol: symbol,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CurrenciesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CurrenciesTable,
      CurrencyRow,
      $$CurrenciesTableFilterComposer,
      $$CurrenciesTableOrderingComposer,
      $$CurrenciesTableAnnotationComposer,
      $$CurrenciesTableCreateCompanionBuilder,
      $$CurrenciesTableUpdateCompanionBuilder,
      (
        CurrencyRow,
        BaseReferences<_$AppDatabase, $CurrenciesTable, CurrencyRow>,
      ),
      CurrencyRow,
      PrefetchHooks Function()
    >;
typedef $$FxRatesTableCreateCompanionBuilder =
    FxRatesCompanion Function({
      required String id,
      required String baseCurrency,
      required String quoteCurrency,
      required Decimal rate,
      required DateTime asOf,
      Value<String?> source,
      Value<int> rowid,
    });
typedef $$FxRatesTableUpdateCompanionBuilder =
    FxRatesCompanion Function({
      Value<String> id,
      Value<String> baseCurrency,
      Value<String> quoteCurrency,
      Value<Decimal> rate,
      Value<DateTime> asOf,
      Value<String?> source,
      Value<int> rowid,
    });

class $$FxRatesTableFilterComposer
    extends Composer<_$AppDatabase, $FxRatesTable> {
  $$FxRatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quoteCurrency => $composableBuilder(
    column: $table.quoteCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String> get rate =>
      $composableBuilder(
        column: $table.rate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FxRatesTableOrderingComposer
    extends Composer<_$AppDatabase, $FxRatesTable> {
  $$FxRatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quoteCurrency => $composableBuilder(
    column: $table.quoteCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rate => $composableBuilder(
    column: $table.rate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FxRatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FxRatesTable> {
  $$FxRatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quoteCurrency => $composableBuilder(
    column: $table.quoteCurrency,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Decimal, String> get rate =>
      $composableBuilder(column: $table.rate, builder: (column) => column);

  GeneratedColumn<DateTime> get asOf =>
      $composableBuilder(column: $table.asOf, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$FxRatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FxRatesTable,
          FxRateRow,
          $$FxRatesTableFilterComposer,
          $$FxRatesTableOrderingComposer,
          $$FxRatesTableAnnotationComposer,
          $$FxRatesTableCreateCompanionBuilder,
          $$FxRatesTableUpdateCompanionBuilder,
          (FxRateRow, BaseReferences<_$AppDatabase, $FxRatesTable, FxRateRow>),
          FxRateRow,
          PrefetchHooks Function()
        > {
  $$FxRatesTableTableManager(_$AppDatabase db, $FxRatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FxRatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FxRatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FxRatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> baseCurrency = const Value.absent(),
                Value<String> quoteCurrency = const Value.absent(),
                Value<Decimal> rate = const Value.absent(),
                Value<DateTime> asOf = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FxRatesCompanion(
                id: id,
                baseCurrency: baseCurrency,
                quoteCurrency: quoteCurrency,
                rate: rate,
                asOf: asOf,
                source: source,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String baseCurrency,
                required String quoteCurrency,
                required Decimal rate,
                required DateTime asOf,
                Value<String?> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FxRatesCompanion.insert(
                id: id,
                baseCurrency: baseCurrency,
                quoteCurrency: quoteCurrency,
                rate: rate,
                asOf: asOf,
                source: source,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FxRatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FxRatesTable,
      FxRateRow,
      $$FxRatesTableFilterComposer,
      $$FxRatesTableOrderingComposer,
      $$FxRatesTableAnnotationComposer,
      $$FxRatesTableCreateCompanionBuilder,
      $$FxRatesTableUpdateCompanionBuilder,
      (FxRateRow, BaseReferences<_$AppDatabase, $FxRatesTable, FxRateRow>),
      FxRateRow,
      PrefetchHooks Function()
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String name,
      required TagKind kind,
      Value<String?> color,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> name,
      Value<TagKind> kind,
      Value<String?> color,
      Value<int> rowid,
    });

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TagKind, TagKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TagKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          TagRow,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagRow, BaseReferences<_$AppDatabase, $TagsTable, TagRow>),
          TagRow,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<TagKind> kind = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                kind: kind,
                color: color,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String name,
                required TagKind kind,
                Value<String?> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                kind: kind,
                color: color,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      TagRow,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagRow, BaseReferences<_$AppDatabase, $TagsTable, TagRow>),
      TagRow,
      PrefetchHooks Function()
    >;
typedef $$TagLinksTableCreateCompanionBuilder =
    TagLinksCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String tagId,
      required String entityTable,
      required String entityId,
      Value<int> rowid,
    });
typedef $$TagLinksTableUpdateCompanionBuilder =
    TagLinksCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> tagId,
      Value<String> entityTable,
      Value<String> entityId,
      Value<int> rowid,
    });

class $$TagLinksTableFilterComposer
    extends Composer<_$AppDatabase, $TagLinksTable> {
  $$TagLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $TagLinksTable> {
  $$TagLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagLinksTable> {
  $$TagLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);
}

class $$TagLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagLinksTable,
          TagLinkRow,
          $$TagLinksTableFilterComposer,
          $$TagLinksTableOrderingComposer,
          $$TagLinksTableAnnotationComposer,
          $$TagLinksTableCreateCompanionBuilder,
          $$TagLinksTableUpdateCompanionBuilder,
          (
            TagLinkRow,
            BaseReferences<_$AppDatabase, $TagLinksTable, TagLinkRow>,
          ),
          TagLinkRow,
          PrefetchHooks Function()
        > {
  $$TagLinksTableTableManager(_$AppDatabase db, $TagLinksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<String> entityTable = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagLinksCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                tagId: tagId,
                entityTable: entityTable,
                entityId: entityId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String tagId,
                required String entityTable,
                required String entityId,
                Value<int> rowid = const Value.absent(),
              }) => TagLinksCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                tagId: tagId,
                entityTable: entityTable,
                entityId: entityId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagLinksTable,
      TagLinkRow,
      $$TagLinksTableFilterComposer,
      $$TagLinksTableOrderingComposer,
      $$TagLinksTableAnnotationComposer,
      $$TagLinksTableCreateCompanionBuilder,
      $$TagLinksTableUpdateCompanionBuilder,
      (TagLinkRow, BaseReferences<_$AppDatabase, $TagLinksTable, TagLinkRow>),
      TagLinkRow,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String name,
      Value<String?> parentId,
      Value<int?> sortOrder,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> name,
      Value<String?> parentId,
      Value<int?> sortOrder,
      Value<int> rowid,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (
            CategoryRow,
            BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow>,
          ),
          CategoryRow,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                parentId: parentId,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String name,
                Value<String?> parentId = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                parentId: parentId,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (
        CategoryRow,
        BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow>,
      ),
      CategoryRow,
      PrefetchHooks Function()
    >;
typedef $$ExpenseCategoriesTableCreateCompanionBuilder =
    ExpenseCategoriesCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String name,
      Value<String?> parentId,
      Value<String?> icon,
      Value<String?> color,
      Value<int?> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowid,
    });
typedef $$ExpenseCategoriesTableUpdateCompanionBuilder =
    ExpenseCategoriesCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> name,
      Value<String?> parentId,
      Value<String?> icon,
      Value<String?> color,
      Value<int?> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowid,
    });

class $$ExpenseCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExpenseCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExpenseCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );
}

class $$ExpenseCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpenseCategoriesTable,
          ExpenseCategoryRow,
          $$ExpenseCategoriesTableFilterComposer,
          $$ExpenseCategoriesTableOrderingComposer,
          $$ExpenseCategoriesTableAnnotationComposer,
          $$ExpenseCategoriesTableCreateCompanionBuilder,
          $$ExpenseCategoriesTableUpdateCompanionBuilder,
          (
            ExpenseCategoryRow,
            BaseReferences<
              _$AppDatabase,
              $ExpenseCategoriesTable,
              ExpenseCategoryRow
            >,
          ),
          ExpenseCategoryRow,
          PrefetchHooks Function()
        > {
  $$ExpenseCategoriesTableTableManager(
    _$AppDatabase db,
    $ExpenseCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpenseCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpenseCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpenseCategoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpenseCategoriesCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                parentId: parentId,
                icon: icon,
                color: color,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String name,
                Value<String?> parentId = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpenseCategoriesCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                parentId: parentId,
                icon: icon,
                color: color,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExpenseCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpenseCategoriesTable,
      ExpenseCategoryRow,
      $$ExpenseCategoriesTableFilterComposer,
      $$ExpenseCategoriesTableOrderingComposer,
      $$ExpenseCategoriesTableAnnotationComposer,
      $$ExpenseCategoriesTableCreateCompanionBuilder,
      $$ExpenseCategoriesTableUpdateCompanionBuilder,
      (
        ExpenseCategoryRow,
        BaseReferences<
          _$AppDatabase,
          $ExpenseCategoriesTable,
          ExpenseCategoryRow
        >,
      ),
      ExpenseCategoryRow,
      PrefetchHooks Function()
    >;
typedef $$GoalsTableCreateCompanionBuilder =
    GoalsCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required GoalType type,
      required String name,
      Value<String?> currency,
      Value<Decimal?> targetAmount,
      Value<DateTime?> targetDate,
      Value<String?> targetAllocationJson,
      Value<String?> note,
      Value<int> rowid,
    });
typedef $$GoalsTableUpdateCompanionBuilder =
    GoalsCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<GoalType> type,
      Value<String> name,
      Value<String?> currency,
      Value<Decimal?> targetAmount,
      Value<DateTime?> targetDate,
      Value<String?> targetAllocationJson,
      Value<String?> note,
      Value<int> rowid,
    });

class $$GoalsTableFilterComposer extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<GoalType, GoalType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal?, Decimal, String> get targetAmount =>
      $composableBuilder(
        column: $table.targetAmount,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetAllocationJson => $composableBuilder(
    column: $table.targetAllocationJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GoalsTableOrderingComposer
    extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetAmount => $composableBuilder(
    column: $table.targetAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetAllocationJson => $composableBuilder(
    column: $table.targetAllocationJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GoalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<GoalType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal?, String> get targetAmount =>
      $composableBuilder(
        column: $table.targetAmount,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get targetDate => $composableBuilder(
    column: $table.targetDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetAllocationJson => $composableBuilder(
    column: $table.targetAllocationJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$GoalsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GoalsTable,
          GoalRow,
          $$GoalsTableFilterComposer,
          $$GoalsTableOrderingComposer,
          $$GoalsTableAnnotationComposer,
          $$GoalsTableCreateCompanionBuilder,
          $$GoalsTableUpdateCompanionBuilder,
          (GoalRow, BaseReferences<_$AppDatabase, $GoalsTable, GoalRow>),
          GoalRow,
          PrefetchHooks Function()
        > {
  $$GoalsTableTableManager(_$AppDatabase db, $GoalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GoalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GoalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GoalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<GoalType> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> currency = const Value.absent(),
                Value<Decimal?> targetAmount = const Value.absent(),
                Value<DateTime?> targetDate = const Value.absent(),
                Value<String?> targetAllocationJson = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GoalsCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                type: type,
                name: name,
                currency: currency,
                targetAmount: targetAmount,
                targetDate: targetDate,
                targetAllocationJson: targetAllocationJson,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required GoalType type,
                required String name,
                Value<String?> currency = const Value.absent(),
                Value<Decimal?> targetAmount = const Value.absent(),
                Value<DateTime?> targetDate = const Value.absent(),
                Value<String?> targetAllocationJson = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GoalsCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                type: type,
                name: name,
                currency: currency,
                targetAmount: targetAmount,
                targetDate: targetDate,
                targetAllocationJson: targetAllocationJson,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GoalsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GoalsTable,
      GoalRow,
      $$GoalsTableFilterComposer,
      $$GoalsTableOrderingComposer,
      $$GoalsTableAnnotationComposer,
      $$GoalsTableCreateCompanionBuilder,
      $$GoalsTableUpdateCompanionBuilder,
      (GoalRow, BaseReferences<_$AppDatabase, $GoalsTable, GoalRow>),
      GoalRow,
      PrefetchHooks Function()
    >;
typedef $$DevicesTableCreateCompanionBuilder =
    DevicesCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String name,
      required DevicePlatform platform,
      Value<String?> appVersion,
      Value<DateTime?> lastSyncAt,
      Value<Hlc?> lastHlc,
      Value<int> rowid,
    });
typedef $$DevicesTableUpdateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> name,
      Value<DevicePlatform> platform,
      Value<String?> appVersion,
      Value<DateTime?> lastSyncAt,
      Value<Hlc?> lastHlc,
      Value<int> rowid,
    });

class $$DevicesTableFilterComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DevicePlatform, DevicePlatform, String>
  get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc?, Hlc, String> get lastHlc =>
      $composableBuilder(
        column: $table.lastHlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$DevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastHlc => $composableBuilder(
    column: $table.lastHlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DevicePlatform, String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc?, String> get lastHlc =>
      $composableBuilder(column: $table.lastHlc, builder: (column) => column);
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DevicesTable,
          DeviceRow,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (DeviceRow, BaseReferences<_$AppDatabase, $DevicesTable, DeviceRow>),
          DeviceRow,
          PrefetchHooks Function()
        > {
  $$DevicesTableTableManager(_$AppDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DevicePlatform> platform = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<Hlc?> lastHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                platform: platform,
                appVersion: appVersion,
                lastSyncAt: lastSyncAt,
                lastHlc: lastHlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String name,
                required DevicePlatform platform,
                Value<String?> appVersion = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<Hlc?> lastHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                name: name,
                platform: platform,
                appVersion: appVersion,
                lastSyncAt: lastSyncAt,
                lastHlc: lastHlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DevicesTable,
      DeviceRow,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (DeviceRow, BaseReferences<_$AppDatabase, $DevicesTable, DeviceRow>),
      DeviceRow,
      PrefetchHooks Function()
    >;
typedef $$OpLogsTableCreateCompanionBuilder =
    OpLogsCompanion Function({
      required String id,
      required String ownerUserId,
      required String deviceId,
      required Hlc hlc,
      required OpKind op,
      required String entityTable,
      required String entityId,
      Value<String?> patchJson,
      Value<DateTime?> syncedAt,
      Value<int> rowid,
    });
typedef $$OpLogsTableUpdateCompanionBuilder =
    OpLogsCompanion Function({
      Value<String> id,
      Value<String> ownerUserId,
      Value<String> deviceId,
      Value<Hlc> hlc,
      Value<OpKind> op,
      Value<String> entityTable,
      Value<String> entityId,
      Value<String?> patchJson,
      Value<DateTime?> syncedAt,
      Value<int> rowid,
    });

class $$OpLogsTableFilterComposer
    extends Composer<_$AppDatabase, $OpLogsTable> {
  $$OpLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<OpKind, OpKind, String> get op =>
      $composableBuilder(
        column: $table.op,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patchJson => $composableBuilder(
    column: $table.patchJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OpLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $OpLogsTable> {
  $$OpLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patchJson => $composableBuilder(
    column: $table.patchJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OpLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OpLogsTable> {
  $$OpLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumnWithTypeConverter<OpKind, String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get patchJson =>
      $composableBuilder(column: $table.patchJson, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$OpLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OpLogsTable,
          OpLogRow,
          $$OpLogsTableFilterComposer,
          $$OpLogsTableOrderingComposer,
          $$OpLogsTableAnnotationComposer,
          $$OpLogsTableCreateCompanionBuilder,
          $$OpLogsTableUpdateCompanionBuilder,
          (OpLogRow, BaseReferences<_$AppDatabase, $OpLogsTable, OpLogRow>),
          OpLogRow,
          PrefetchHooks Function()
        > {
  $$OpLogsTableTableManager(_$AppDatabase db, $OpLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OpLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OpLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OpLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerUserId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<OpKind> op = const Value.absent(),
                Value<String> entityTable = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String?> patchJson = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OpLogsCompanion(
                id: id,
                ownerUserId: ownerUserId,
                deviceId: deviceId,
                hlc: hlc,
                op: op,
                entityTable: entityTable,
                entityId: entityId,
                patchJson: patchJson,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerUserId,
                required String deviceId,
                required Hlc hlc,
                required OpKind op,
                required String entityTable,
                required String entityId,
                Value<String?> patchJson = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OpLogsCompanion.insert(
                id: id,
                ownerUserId: ownerUserId,
                deviceId: deviceId,
                hlc: hlc,
                op: op,
                entityTable: entityTable,
                entityId: entityId,
                patchJson: patchJson,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OpLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OpLogsTable,
      OpLogRow,
      $$OpLogsTableFilterComposer,
      $$OpLogsTableOrderingComposer,
      $$OpLogsTableAnnotationComposer,
      $$OpLogsTableCreateCompanionBuilder,
      $$OpLogsTableUpdateCompanionBuilder,
      (OpLogRow, BaseReferences<_$AppDatabase, $OpLogsTable, OpLogRow>),
      OpLogRow,
      PrefetchHooks Function()
    >;
typedef $$MarketQuotesTableCreateCompanionBuilder =
    MarketQuotesCompanion Function({
      required String symbol,
      required String source,
      required String currency,
      required String price,
      Value<String?> previousClose,
      Value<String?> openPrice,
      Value<String?> dayHigh,
      Value<String?> dayLow,
      Value<int?> volume,
      Value<String?> exchange,
      required DateTime asOf,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$MarketQuotesTableUpdateCompanionBuilder =
    MarketQuotesCompanion Function({
      Value<String> symbol,
      Value<String> source,
      Value<String> currency,
      Value<String> price,
      Value<String?> previousClose,
      Value<String?> openPrice,
      Value<String?> dayHigh,
      Value<String?> dayLow,
      Value<int?> volume,
      Value<String?> exchange,
      Value<DateTime> asOf,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$MarketQuotesTableFilterComposer
    extends Composer<_$AppDatabase, $MarketQuotesTable> {
  $$MarketQuotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousClose => $composableBuilder(
    column: $table.previousClose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get openPrice => $composableBuilder(
    column: $table.openPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayHigh => $composableBuilder(
    column: $table.dayHigh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayLow => $composableBuilder(
    column: $table.dayLow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exchange => $composableBuilder(
    column: $table.exchange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MarketQuotesTableOrderingComposer
    extends Composer<_$AppDatabase, $MarketQuotesTable> {
  $$MarketQuotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousClose => $composableBuilder(
    column: $table.previousClose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get openPrice => $composableBuilder(
    column: $table.openPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayHigh => $composableBuilder(
    column: $table.dayHigh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayLow => $composableBuilder(
    column: $table.dayLow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exchange => $composableBuilder(
    column: $table.exchange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MarketQuotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MarketQuotesTable> {
  $$MarketQuotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get previousClose => $composableBuilder(
    column: $table.previousClose,
    builder: (column) => column,
  );

  GeneratedColumn<String> get openPrice =>
      $composableBuilder(column: $table.openPrice, builder: (column) => column);

  GeneratedColumn<String> get dayHigh =>
      $composableBuilder(column: $table.dayHigh, builder: (column) => column);

  GeneratedColumn<String> get dayLow =>
      $composableBuilder(column: $table.dayLow, builder: (column) => column);

  GeneratedColumn<int> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);

  GeneratedColumn<String> get exchange =>
      $composableBuilder(column: $table.exchange, builder: (column) => column);

  GeneratedColumn<DateTime> get asOf =>
      $composableBuilder(column: $table.asOf, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$MarketQuotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MarketQuotesTable,
          MarketQuoteRow,
          $$MarketQuotesTableFilterComposer,
          $$MarketQuotesTableOrderingComposer,
          $$MarketQuotesTableAnnotationComposer,
          $$MarketQuotesTableCreateCompanionBuilder,
          $$MarketQuotesTableUpdateCompanionBuilder,
          (
            MarketQuoteRow,
            BaseReferences<_$AppDatabase, $MarketQuotesTable, MarketQuoteRow>,
          ),
          MarketQuoteRow,
          PrefetchHooks Function()
        > {
  $$MarketQuotesTableTableManager(_$AppDatabase db, $MarketQuotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MarketQuotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MarketQuotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MarketQuotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> symbol = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> price = const Value.absent(),
                Value<String?> previousClose = const Value.absent(),
                Value<String?> openPrice = const Value.absent(),
                Value<String?> dayHigh = const Value.absent(),
                Value<String?> dayLow = const Value.absent(),
                Value<int?> volume = const Value.absent(),
                Value<String?> exchange = const Value.absent(),
                Value<DateTime> asOf = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MarketQuotesCompanion(
                symbol: symbol,
                source: source,
                currency: currency,
                price: price,
                previousClose: previousClose,
                openPrice: openPrice,
                dayHigh: dayHigh,
                dayLow: dayLow,
                volume: volume,
                exchange: exchange,
                asOf: asOf,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required String source,
                required String currency,
                required String price,
                Value<String?> previousClose = const Value.absent(),
                Value<String?> openPrice = const Value.absent(),
                Value<String?> dayHigh = const Value.absent(),
                Value<String?> dayLow = const Value.absent(),
                Value<int?> volume = const Value.absent(),
                Value<String?> exchange = const Value.absent(),
                required DateTime asOf,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => MarketQuotesCompanion.insert(
                symbol: symbol,
                source: source,
                currency: currency,
                price: price,
                previousClose: previousClose,
                openPrice: openPrice,
                dayHigh: dayHigh,
                dayLow: dayLow,
                volume: volume,
                exchange: exchange,
                asOf: asOf,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MarketQuotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MarketQuotesTable,
      MarketQuoteRow,
      $$MarketQuotesTableFilterComposer,
      $$MarketQuotesTableOrderingComposer,
      $$MarketQuotesTableAnnotationComposer,
      $$MarketQuotesTableCreateCompanionBuilder,
      $$MarketQuotesTableUpdateCompanionBuilder,
      (
        MarketQuoteRow,
        BaseReferences<_$AppDatabase, $MarketQuotesTable, MarketQuoteRow>,
      ),
      MarketQuoteRow,
      PrefetchHooks Function()
    >;
typedef $$MarketHistoryBarsTableCreateCompanionBuilder =
    MarketHistoryBarsCompanion Function({
      required String symbol,
      required String interval,
      required DateTime asOf,
      required String source,
      required String openPrice,
      required String high,
      required String low,
      required String closePrice,
      Value<int?> volume,
      Value<String?> adjustedClose,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$MarketHistoryBarsTableUpdateCompanionBuilder =
    MarketHistoryBarsCompanion Function({
      Value<String> symbol,
      Value<String> interval,
      Value<DateTime> asOf,
      Value<String> source,
      Value<String> openPrice,
      Value<String> high,
      Value<String> low,
      Value<String> closePrice,
      Value<int?> volume,
      Value<String?> adjustedClose,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$MarketHistoryBarsTableFilterComposer
    extends Composer<_$AppDatabase, $MarketHistoryBarsTable> {
  $$MarketHistoryBarsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get interval => $composableBuilder(
    column: $table.interval,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get openPrice => $composableBuilder(
    column: $table.openPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get high => $composableBuilder(
    column: $table.high,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get low => $composableBuilder(
    column: $table.low,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get closePrice => $composableBuilder(
    column: $table.closePrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get adjustedClose => $composableBuilder(
    column: $table.adjustedClose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MarketHistoryBarsTableOrderingComposer
    extends Composer<_$AppDatabase, $MarketHistoryBarsTable> {
  $$MarketHistoryBarsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get interval => $composableBuilder(
    column: $table.interval,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get openPrice => $composableBuilder(
    column: $table.openPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get high => $composableBuilder(
    column: $table.high,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get low => $composableBuilder(
    column: $table.low,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get closePrice => $composableBuilder(
    column: $table.closePrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get adjustedClose => $composableBuilder(
    column: $table.adjustedClose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MarketHistoryBarsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MarketHistoryBarsTable> {
  $$MarketHistoryBarsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get interval =>
      $composableBuilder(column: $table.interval, builder: (column) => column);

  GeneratedColumn<DateTime> get asOf =>
      $composableBuilder(column: $table.asOf, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get openPrice =>
      $composableBuilder(column: $table.openPrice, builder: (column) => column);

  GeneratedColumn<String> get high =>
      $composableBuilder(column: $table.high, builder: (column) => column);

  GeneratedColumn<String> get low =>
      $composableBuilder(column: $table.low, builder: (column) => column);

  GeneratedColumn<String> get closePrice => $composableBuilder(
    column: $table.closePrice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);

  GeneratedColumn<String> get adjustedClose => $composableBuilder(
    column: $table.adjustedClose,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$MarketHistoryBarsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MarketHistoryBarsTable,
          MarketHistoryRow,
          $$MarketHistoryBarsTableFilterComposer,
          $$MarketHistoryBarsTableOrderingComposer,
          $$MarketHistoryBarsTableAnnotationComposer,
          $$MarketHistoryBarsTableCreateCompanionBuilder,
          $$MarketHistoryBarsTableUpdateCompanionBuilder,
          (
            MarketHistoryRow,
            BaseReferences<
              _$AppDatabase,
              $MarketHistoryBarsTable,
              MarketHistoryRow
            >,
          ),
          MarketHistoryRow,
          PrefetchHooks Function()
        > {
  $$MarketHistoryBarsTableTableManager(
    _$AppDatabase db,
    $MarketHistoryBarsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MarketHistoryBarsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MarketHistoryBarsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MarketHistoryBarsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> symbol = const Value.absent(),
                Value<String> interval = const Value.absent(),
                Value<DateTime> asOf = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> openPrice = const Value.absent(),
                Value<String> high = const Value.absent(),
                Value<String> low = const Value.absent(),
                Value<String> closePrice = const Value.absent(),
                Value<int?> volume = const Value.absent(),
                Value<String?> adjustedClose = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MarketHistoryBarsCompanion(
                symbol: symbol,
                interval: interval,
                asOf: asOf,
                source: source,
                openPrice: openPrice,
                high: high,
                low: low,
                closePrice: closePrice,
                volume: volume,
                adjustedClose: adjustedClose,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required String interval,
                required DateTime asOf,
                required String source,
                required String openPrice,
                required String high,
                required String low,
                required String closePrice,
                Value<int?> volume = const Value.absent(),
                Value<String?> adjustedClose = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => MarketHistoryBarsCompanion.insert(
                symbol: symbol,
                interval: interval,
                asOf: asOf,
                source: source,
                openPrice: openPrice,
                high: high,
                low: low,
                closePrice: closePrice,
                volume: volume,
                adjustedClose: adjustedClose,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MarketHistoryBarsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MarketHistoryBarsTable,
      MarketHistoryRow,
      $$MarketHistoryBarsTableFilterComposer,
      $$MarketHistoryBarsTableOrderingComposer,
      $$MarketHistoryBarsTableAnnotationComposer,
      $$MarketHistoryBarsTableCreateCompanionBuilder,
      $$MarketHistoryBarsTableUpdateCompanionBuilder,
      (
        MarketHistoryRow,
        BaseReferences<
          _$AppDatabase,
          $MarketHistoryBarsTable,
          MarketHistoryRow
        >,
      ),
      MarketHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$MarketSymbolSearchesTableCreateCompanionBuilder =
    MarketSymbolSearchesCompanion Function({
      required String query,
      required String source,
      required String results,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$MarketSymbolSearchesTableUpdateCompanionBuilder =
    MarketSymbolSearchesCompanion Function({
      Value<String> query,
      Value<String> source,
      Value<String> results,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$MarketSymbolSearchesTableFilterComposer
    extends Composer<_$AppDatabase, $MarketSymbolSearchesTable> {
  $$MarketSymbolSearchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get results => $composableBuilder(
    column: $table.results,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MarketSymbolSearchesTableOrderingComposer
    extends Composer<_$AppDatabase, $MarketSymbolSearchesTable> {
  $$MarketSymbolSearchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get results => $composableBuilder(
    column: $table.results,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MarketSymbolSearchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MarketSymbolSearchesTable> {
  $$MarketSymbolSearchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get results =>
      $composableBuilder(column: $table.results, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$MarketSymbolSearchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MarketSymbolSearchesTable,
          MarketSymbolSearchRow,
          $$MarketSymbolSearchesTableFilterComposer,
          $$MarketSymbolSearchesTableOrderingComposer,
          $$MarketSymbolSearchesTableAnnotationComposer,
          $$MarketSymbolSearchesTableCreateCompanionBuilder,
          $$MarketSymbolSearchesTableUpdateCompanionBuilder,
          (
            MarketSymbolSearchRow,
            BaseReferences<
              _$AppDatabase,
              $MarketSymbolSearchesTable,
              MarketSymbolSearchRow
            >,
          ),
          MarketSymbolSearchRow,
          PrefetchHooks Function()
        > {
  $$MarketSymbolSearchesTableTableManager(
    _$AppDatabase db,
    $MarketSymbolSearchesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MarketSymbolSearchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MarketSymbolSearchesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MarketSymbolSearchesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> query = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> results = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MarketSymbolSearchesCompanion(
                query: query,
                source: source,
                results: results,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String query,
                required String source,
                required String results,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => MarketSymbolSearchesCompanion.insert(
                query: query,
                source: source,
                results: results,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MarketSymbolSearchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MarketSymbolSearchesTable,
      MarketSymbolSearchRow,
      $$MarketSymbolSearchesTableFilterComposer,
      $$MarketSymbolSearchesTableOrderingComposer,
      $$MarketSymbolSearchesTableAnnotationComposer,
      $$MarketSymbolSearchesTableCreateCompanionBuilder,
      $$MarketSymbolSearchesTableUpdateCompanionBuilder,
      (
        MarketSymbolSearchRow,
        BaseReferences<
          _$AppDatabase,
          $MarketSymbolSearchesTable,
          MarketSymbolSearchRow
        >,
      ),
      MarketSymbolSearchRow,
      PrefetchHooks Function()
    >;
typedef $$SecuritiesCatalogTableCreateCompanionBuilder =
    SecuritiesCatalogCompanion Function({
      required String id,
      required String symbol,
      required String market,
      required AssetType type,
      required String currency,
      Value<String?> nameEn,
      Value<String?> nameCn,
      Value<String?> pinyin,
      Value<String?> pinyinInitials,
      Value<String?> aliases,
      Value<int> rowid,
    });
typedef $$SecuritiesCatalogTableUpdateCompanionBuilder =
    SecuritiesCatalogCompanion Function({
      Value<String> id,
      Value<String> symbol,
      Value<String> market,
      Value<AssetType> type,
      Value<String> currency,
      Value<String?> nameEn,
      Value<String?> nameCn,
      Value<String?> pinyin,
      Value<String?> pinyinInitials,
      Value<String?> aliases,
      Value<int> rowid,
    });

class $$SecuritiesCatalogTableFilterComposer
    extends Composer<_$AppDatabase, $SecuritiesCatalogTable> {
  $$SecuritiesCatalogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get market => $composableBuilder(
    column: $table.market,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AssetType, AssetType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameCn => $composableBuilder(
    column: $table.nameCn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pinyin => $composableBuilder(
    column: $table.pinyin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pinyinInitials => $composableBuilder(
    column: $table.pinyinInitials,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SecuritiesCatalogTableOrderingComposer
    extends Composer<_$AppDatabase, $SecuritiesCatalogTable> {
  $$SecuritiesCatalogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get market => $composableBuilder(
    column: $table.market,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameCn => $composableBuilder(
    column: $table.nameCn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pinyin => $composableBuilder(
    column: $table.pinyin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pinyinInitials => $composableBuilder(
    column: $table.pinyinInitials,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SecuritiesCatalogTableAnnotationComposer
    extends Composer<_$AppDatabase, $SecuritiesCatalogTable> {
  $$SecuritiesCatalogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get market =>
      $composableBuilder(column: $table.market, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AssetType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get nameEn =>
      $composableBuilder(column: $table.nameEn, builder: (column) => column);

  GeneratedColumn<String> get nameCn =>
      $composableBuilder(column: $table.nameCn, builder: (column) => column);

  GeneratedColumn<String> get pinyin =>
      $composableBuilder(column: $table.pinyin, builder: (column) => column);

  GeneratedColumn<String> get pinyinInitials => $composableBuilder(
    column: $table.pinyinInitials,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aliases =>
      $composableBuilder(column: $table.aliases, builder: (column) => column);
}

class $$SecuritiesCatalogTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SecuritiesCatalogTable,
          SecuritiesCatalogRow,
          $$SecuritiesCatalogTableFilterComposer,
          $$SecuritiesCatalogTableOrderingComposer,
          $$SecuritiesCatalogTableAnnotationComposer,
          $$SecuritiesCatalogTableCreateCompanionBuilder,
          $$SecuritiesCatalogTableUpdateCompanionBuilder,
          (
            SecuritiesCatalogRow,
            BaseReferences<
              _$AppDatabase,
              $SecuritiesCatalogTable,
              SecuritiesCatalogRow
            >,
          ),
          SecuritiesCatalogRow,
          PrefetchHooks Function()
        > {
  $$SecuritiesCatalogTableTableManager(
    _$AppDatabase db,
    $SecuritiesCatalogTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SecuritiesCatalogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SecuritiesCatalogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SecuritiesCatalogTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> symbol = const Value.absent(),
                Value<String> market = const Value.absent(),
                Value<AssetType> type = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String?> nameEn = const Value.absent(),
                Value<String?> nameCn = const Value.absent(),
                Value<String?> pinyin = const Value.absent(),
                Value<String?> pinyinInitials = const Value.absent(),
                Value<String?> aliases = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SecuritiesCatalogCompanion(
                id: id,
                symbol: symbol,
                market: market,
                type: type,
                currency: currency,
                nameEn: nameEn,
                nameCn: nameCn,
                pinyin: pinyin,
                pinyinInitials: pinyinInitials,
                aliases: aliases,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String symbol,
                required String market,
                required AssetType type,
                required String currency,
                Value<String?> nameEn = const Value.absent(),
                Value<String?> nameCn = const Value.absent(),
                Value<String?> pinyin = const Value.absent(),
                Value<String?> pinyinInitials = const Value.absent(),
                Value<String?> aliases = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SecuritiesCatalogCompanion.insert(
                id: id,
                symbol: symbol,
                market: market,
                type: type,
                currency: currency,
                nameEn: nameEn,
                nameCn: nameCn,
                pinyin: pinyin,
                pinyinInitials: pinyinInitials,
                aliases: aliases,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SecuritiesCatalogTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SecuritiesCatalogTable,
      SecuritiesCatalogRow,
      $$SecuritiesCatalogTableFilterComposer,
      $$SecuritiesCatalogTableOrderingComposer,
      $$SecuritiesCatalogTableAnnotationComposer,
      $$SecuritiesCatalogTableCreateCompanionBuilder,
      $$SecuritiesCatalogTableUpdateCompanionBuilder,
      (
        SecuritiesCatalogRow,
        BaseReferences<
          _$AppDatabase,
          $SecuritiesCatalogTable,
          SecuritiesCatalogRow
        >,
      ),
      SecuritiesCatalogRow,
      PrefetchHooks Function()
    >;
typedef $$SecuritiesCatalogMetaTableCreateCompanionBuilder =
    SecuritiesCatalogMetaCompanion Function({
      Value<int> id,
      required String version,
      required String checksum,
      required int rowCount,
      required DateTime loadedAt,
    });
typedef $$SecuritiesCatalogMetaTableUpdateCompanionBuilder =
    SecuritiesCatalogMetaCompanion Function({
      Value<int> id,
      Value<String> version,
      Value<String> checksum,
      Value<int> rowCount,
      Value<DateTime> loadedAt,
    });

class $$SecuritiesCatalogMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SecuritiesCatalogMetaTable> {
  $$SecuritiesCatalogMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowCount => $composableBuilder(
    column: $table.rowCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get loadedAt => $composableBuilder(
    column: $table.loadedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SecuritiesCatalogMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SecuritiesCatalogMetaTable> {
  $$SecuritiesCatalogMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowCount => $composableBuilder(
    column: $table.rowCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get loadedAt => $composableBuilder(
    column: $table.loadedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SecuritiesCatalogMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SecuritiesCatalogMetaTable> {
  $$SecuritiesCatalogMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);

  GeneratedColumn<int> get rowCount =>
      $composableBuilder(column: $table.rowCount, builder: (column) => column);

  GeneratedColumn<DateTime> get loadedAt =>
      $composableBuilder(column: $table.loadedAt, builder: (column) => column);
}

class $$SecuritiesCatalogMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SecuritiesCatalogMetaTable,
          SecuritiesCatalogMetaRow,
          $$SecuritiesCatalogMetaTableFilterComposer,
          $$SecuritiesCatalogMetaTableOrderingComposer,
          $$SecuritiesCatalogMetaTableAnnotationComposer,
          $$SecuritiesCatalogMetaTableCreateCompanionBuilder,
          $$SecuritiesCatalogMetaTableUpdateCompanionBuilder,
          (
            SecuritiesCatalogMetaRow,
            BaseReferences<
              _$AppDatabase,
              $SecuritiesCatalogMetaTable,
              SecuritiesCatalogMetaRow
            >,
          ),
          SecuritiesCatalogMetaRow,
          PrefetchHooks Function()
        > {
  $$SecuritiesCatalogMetaTableTableManager(
    _$AppDatabase db,
    $SecuritiesCatalogMetaTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SecuritiesCatalogMetaTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SecuritiesCatalogMetaTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SecuritiesCatalogMetaTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> checksum = const Value.absent(),
                Value<int> rowCount = const Value.absent(),
                Value<DateTime> loadedAt = const Value.absent(),
              }) => SecuritiesCatalogMetaCompanion(
                id: id,
                version: version,
                checksum: checksum,
                rowCount: rowCount,
                loadedAt: loadedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String version,
                required String checksum,
                required int rowCount,
                required DateTime loadedAt,
              }) => SecuritiesCatalogMetaCompanion.insert(
                id: id,
                version: version,
                checksum: checksum,
                rowCount: rowCount,
                loadedAt: loadedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SecuritiesCatalogMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SecuritiesCatalogMetaTable,
      SecuritiesCatalogMetaRow,
      $$SecuritiesCatalogMetaTableFilterComposer,
      $$SecuritiesCatalogMetaTableOrderingComposer,
      $$SecuritiesCatalogMetaTableAnnotationComposer,
      $$SecuritiesCatalogMetaTableCreateCompanionBuilder,
      $$SecuritiesCatalogMetaTableUpdateCompanionBuilder,
      (
        SecuritiesCatalogMetaRow,
        BaseReferences<
          _$AppDatabase,
          $SecuritiesCatalogMetaTable,
          SecuritiesCatalogMetaRow
        >,
      ),
      SecuritiesCatalogMetaRow,
      PrefetchHooks Function()
    >;
typedef $$JournalEntriesTableCreateCompanionBuilder =
    JournalEntriesCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required DateTime date,
      Value<DateTime?> settledOn,
      required String narration,
      Value<String?> payee,
      Value<EntryFlag> flag,
      Value<String> tagIdsJson,
      Value<int> rowid,
    });
typedef $$JournalEntriesTableUpdateCompanionBuilder =
    JournalEntriesCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<DateTime> date,
      Value<DateTime?> settledOn,
      Value<String> narration,
      Value<String?> payee,
      Value<EntryFlag> flag,
      Value<String> tagIdsJson,
      Value<int> rowid,
    });

class $$JournalEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get settledOn => $composableBuilder(
    column: $table.settledOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get narration => $composableBuilder(
    column: $table.narration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payee => $composableBuilder(
    column: $table.payee,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EntryFlag, EntryFlag, String> get flag =>
      $composableBuilder(
        column: $table.flag,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get tagIdsJson => $composableBuilder(
    column: $table.tagIdsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$JournalEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get settledOn => $composableBuilder(
    column: $table.settledOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get narration => $composableBuilder(
    column: $table.narration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payee => $composableBuilder(
    column: $table.payee,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get flag => $composableBuilder(
    column: $table.flag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagIdsJson => $composableBuilder(
    column: $table.tagIdsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JournalEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<DateTime> get settledOn =>
      $composableBuilder(column: $table.settledOn, builder: (column) => column);

  GeneratedColumn<String> get narration =>
      $composableBuilder(column: $table.narration, builder: (column) => column);

  GeneratedColumn<String> get payee =>
      $composableBuilder(column: $table.payee, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EntryFlag, String> get flag =>
      $composableBuilder(column: $table.flag, builder: (column) => column);

  GeneratedColumn<String> get tagIdsJson => $composableBuilder(
    column: $table.tagIdsJson,
    builder: (column) => column,
  );
}

class $$JournalEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $JournalEntriesTable,
          JournalEntryRow,
          $$JournalEntriesTableFilterComposer,
          $$JournalEntriesTableOrderingComposer,
          $$JournalEntriesTableAnnotationComposer,
          $$JournalEntriesTableCreateCompanionBuilder,
          $$JournalEntriesTableUpdateCompanionBuilder,
          (
            JournalEntryRow,
            BaseReferences<
              _$AppDatabase,
              $JournalEntriesTable,
              JournalEntryRow
            >,
          ),
          JournalEntryRow,
          PrefetchHooks Function()
        > {
  $$JournalEntriesTableTableManager(
    _$AppDatabase db,
    $JournalEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<DateTime?> settledOn = const Value.absent(),
                Value<String> narration = const Value.absent(),
                Value<String?> payee = const Value.absent(),
                Value<EntryFlag> flag = const Value.absent(),
                Value<String> tagIdsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                date: date,
                settledOn: settledOn,
                narration: narration,
                payee: payee,
                flag: flag,
                tagIdsJson: tagIdsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required DateTime date,
                Value<DateTime?> settledOn = const Value.absent(),
                required String narration,
                Value<String?> payee = const Value.absent(),
                Value<EntryFlag> flag = const Value.absent(),
                Value<String> tagIdsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                date: date,
                settledOn: settledOn,
                narration: narration,
                payee: payee,
                flag: flag,
                tagIdsJson: tagIdsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$JournalEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $JournalEntriesTable,
      JournalEntryRow,
      $$JournalEntriesTableFilterComposer,
      $$JournalEntriesTableOrderingComposer,
      $$JournalEntriesTableAnnotationComposer,
      $$JournalEntriesTableCreateCompanionBuilder,
      $$JournalEntriesTableUpdateCompanionBuilder,
      (
        JournalEntryRow,
        BaseReferences<_$AppDatabase, $JournalEntriesTable, JournalEntryRow>,
      ),
      JournalEntryRow,
      PrefetchHooks Function()
    >;
typedef $$PostingsTableCreateCompanionBuilder =
    PostingsCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String journalEntryId,
      required int position,
      required String accountId,
      required Decimal units,
      required String unit,
      Value<Decimal?> costPerUnit,
      Value<String?> costCurrency,
      Value<String?> costLotId,
      Value<DateTime?> costAcquiredOn,
      Value<Decimal?> pricePerUnit,
      Value<String?> priceCurrency,
      Value<int> rowid,
    });
typedef $$PostingsTableUpdateCompanionBuilder =
    PostingsCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> journalEntryId,
      Value<int> position,
      Value<String> accountId,
      Value<Decimal> units,
      Value<String> unit,
      Value<Decimal?> costPerUnit,
      Value<String?> costCurrency,
      Value<String?> costLotId,
      Value<DateTime?> costAcquiredOn,
      Value<Decimal?> pricePerUnit,
      Value<String?> priceCurrency,
      Value<int> rowid,
    });

class $$PostingsTableFilterComposer
    extends Composer<_$AppDatabase, $PostingsTable> {
  $$PostingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get journalEntryId => $composableBuilder(
    column: $table.journalEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String> get units =>
      $composableBuilder(
        column: $table.units,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal?, Decimal, String> get costPerUnit =>
      $composableBuilder(
        column: $table.costPerUnit,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get costCurrency => $composableBuilder(
    column: $table.costCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get costLotId => $composableBuilder(
    column: $table.costLotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get costAcquiredOn => $composableBuilder(
    column: $table.costAcquiredOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal?, Decimal, String> get pricePerUnit =>
      $composableBuilder(
        column: $table.pricePerUnit,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get priceCurrency => $composableBuilder(
    column: $table.priceCurrency,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PostingsTableOrderingComposer
    extends Composer<_$AppDatabase, $PostingsTable> {
  $$PostingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get journalEntryId => $composableBuilder(
    column: $table.journalEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get units => $composableBuilder(
    column: $table.units,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get costPerUnit => $composableBuilder(
    column: $table.costPerUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get costCurrency => $composableBuilder(
    column: $table.costCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get costLotId => $composableBuilder(
    column: $table.costLotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get costAcquiredOn => $composableBuilder(
    column: $table.costAcquiredOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pricePerUnit => $composableBuilder(
    column: $table.pricePerUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priceCurrency => $composableBuilder(
    column: $table.priceCurrency,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PostingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PostingsTable> {
  $$PostingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get journalEntryId => $composableBuilder(
    column: $table.journalEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal, String> get units =>
      $composableBuilder(column: $table.units, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Decimal?, String> get costPerUnit =>
      $composableBuilder(
        column: $table.costPerUnit,
        builder: (column) => column,
      );

  GeneratedColumn<String> get costCurrency => $composableBuilder(
    column: $table.costCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<String> get costLotId =>
      $composableBuilder(column: $table.costLotId, builder: (column) => column);

  GeneratedColumn<DateTime> get costAcquiredOn => $composableBuilder(
    column: $table.costAcquiredOn,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Decimal?, String> get pricePerUnit =>
      $composableBuilder(
        column: $table.pricePerUnit,
        builder: (column) => column,
      );

  GeneratedColumn<String> get priceCurrency => $composableBuilder(
    column: $table.priceCurrency,
    builder: (column) => column,
  );
}

class $$PostingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PostingsTable,
          PostingRow,
          $$PostingsTableFilterComposer,
          $$PostingsTableOrderingComposer,
          $$PostingsTableAnnotationComposer,
          $$PostingsTableCreateCompanionBuilder,
          $$PostingsTableUpdateCompanionBuilder,
          (
            PostingRow,
            BaseReferences<_$AppDatabase, $PostingsTable, PostingRow>,
          ),
          PostingRow,
          PrefetchHooks Function()
        > {
  $$PostingsTableTableManager(_$AppDatabase db, $PostingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PostingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PostingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PostingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> journalEntryId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<Decimal> units = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<Decimal?> costPerUnit = const Value.absent(),
                Value<String?> costCurrency = const Value.absent(),
                Value<String?> costLotId = const Value.absent(),
                Value<DateTime?> costAcquiredOn = const Value.absent(),
                Value<Decimal?> pricePerUnit = const Value.absent(),
                Value<String?> priceCurrency = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PostingsCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                journalEntryId: journalEntryId,
                position: position,
                accountId: accountId,
                units: units,
                unit: unit,
                costPerUnit: costPerUnit,
                costCurrency: costCurrency,
                costLotId: costLotId,
                costAcquiredOn: costAcquiredOn,
                pricePerUnit: pricePerUnit,
                priceCurrency: priceCurrency,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String journalEntryId,
                required int position,
                required String accountId,
                required Decimal units,
                required String unit,
                Value<Decimal?> costPerUnit = const Value.absent(),
                Value<String?> costCurrency = const Value.absent(),
                Value<String?> costLotId = const Value.absent(),
                Value<DateTime?> costAcquiredOn = const Value.absent(),
                Value<Decimal?> pricePerUnit = const Value.absent(),
                Value<String?> priceCurrency = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PostingsCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                journalEntryId: journalEntryId,
                position: position,
                accountId: accountId,
                units: units,
                unit: unit,
                costPerUnit: costPerUnit,
                costCurrency: costCurrency,
                costLotId: costLotId,
                costAcquiredOn: costAcquiredOn,
                pricePerUnit: pricePerUnit,
                priceCurrency: priceCurrency,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PostingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PostingsTable,
      PostingRow,
      $$PostingsTableFilterComposer,
      $$PostingsTableOrderingComposer,
      $$PostingsTableAnnotationComposer,
      $$PostingsTableCreateCompanionBuilder,
      $$PostingsTableUpdateCompanionBuilder,
      (PostingRow, BaseReferences<_$AppDatabase, $PostingsTable, PostingRow>),
      PostingRow,
      PrefetchHooks Function()
    >;
typedef $$PricesTableCreateCompanionBuilder =
    PricesCompanion Function({
      required String ownerUserId,
      required DateTime updatedAt,
      required String updatedByDevice,
      required Hlc hlc,
      Value<DateTime?> deletedAt,
      required String id,
      required String unit,
      required String quoteCurrency,
      required DateTime observedOn,
      required Decimal perUnit,
      required String source,
      Value<int> rowid,
    });
typedef $$PricesTableUpdateCompanionBuilder =
    PricesCompanion Function({
      Value<String> ownerUserId,
      Value<DateTime> updatedAt,
      Value<String> updatedByDevice,
      Value<Hlc> hlc,
      Value<DateTime?> deletedAt,
      Value<String> id,
      Value<String> unit,
      Value<String> quoteCurrency,
      Value<DateTime> observedOn,
      Value<Decimal> perUnit,
      Value<String> source,
      Value<int> rowid,
    });

class $$PricesTableFilterComposer
    extends Composer<_$AppDatabase, $PricesTable> {
  $$PricesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Hlc, Hlc, String> get hlc =>
      $composableBuilder(
        column: $table.hlc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quoteCurrency => $composableBuilder(
    column: $table.quoteCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get observedOn => $composableBuilder(
    column: $table.observedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Decimal, Decimal, String> get perUnit =>
      $composableBuilder(
        column: $table.perUnit,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PricesTableOrderingComposer
    extends Composer<_$AppDatabase, $PricesTable> {
  $$PricesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quoteCurrency => $composableBuilder(
    column: $table.quoteCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get observedOn => $composableBuilder(
    column: $table.observedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get perUnit => $composableBuilder(
    column: $table.perUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PricesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PricesTable> {
  $$PricesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDevice => $composableBuilder(
    column: $table.updatedByDevice,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Hlc, String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get quoteCurrency => $composableBuilder(
    column: $table.quoteCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get observedOn => $composableBuilder(
    column: $table.observedOn,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Decimal, String> get perUnit =>
      $composableBuilder(column: $table.perUnit, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$PricesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PricesTable,
          PriceRow,
          $$PricesTableFilterComposer,
          $$PricesTableOrderingComposer,
          $$PricesTableAnnotationComposer,
          $$PricesTableCreateCompanionBuilder,
          $$PricesTableUpdateCompanionBuilder,
          (PriceRow, BaseReferences<_$AppDatabase, $PricesTable, PriceRow>),
          PriceRow,
          PrefetchHooks Function()
        > {
  $$PricesTableTableManager(_$AppDatabase db, $PricesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PricesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PricesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PricesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> updatedByDevice = const Value.absent(),
                Value<Hlc> hlc = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String> quoteCurrency = const Value.absent(),
                Value<DateTime> observedOn = const Value.absent(),
                Value<Decimal> perUnit = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PricesCompanion(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                unit: unit,
                quoteCurrency: quoteCurrency,
                observedOn: observedOn,
                perUnit: perUnit,
                source: source,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required DateTime updatedAt,
                required String updatedByDevice,
                required Hlc hlc,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String id,
                required String unit,
                required String quoteCurrency,
                required DateTime observedOn,
                required Decimal perUnit,
                required String source,
                Value<int> rowid = const Value.absent(),
              }) => PricesCompanion.insert(
                ownerUserId: ownerUserId,
                updatedAt: updatedAt,
                updatedByDevice: updatedByDevice,
                hlc: hlc,
                deletedAt: deletedAt,
                id: id,
                unit: unit,
                quoteCurrency: quoteCurrency,
                observedOn: observedOn,
                perUnit: perUnit,
                source: source,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PricesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PricesTable,
      PriceRow,
      $$PricesTableFilterComposer,
      $$PricesTableOrderingComposer,
      $$PricesTableAnnotationComposer,
      $$PricesTableCreateCompanionBuilder,
      $$PricesTableUpdateCompanionBuilder,
      (PriceRow, BaseReferences<_$AppDatabase, $PricesTable, PriceRow>),
      PriceRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$SettingsTableTableTableManager get settingsTable =>
      $$SettingsTableTableTableManager(_db, _db.settingsTable);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$AssetsTableTableManager get assets =>
      $$AssetsTableTableManager(_db, _db.assets);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$LiabilitiesTableTableManager get liabilities =>
      $$LiabilitiesTableTableManager(_db, _db.liabilities);
  $$AmortizationEntriesTableTableManager get amortizationEntries =>
      $$AmortizationEntriesTableTableManager(_db, _db.amortizationEntries);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db, _db.currencies);
  $$FxRatesTableTableManager get fxRates =>
      $$FxRatesTableTableManager(_db, _db.fxRates);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$TagLinksTableTableManager get tagLinks =>
      $$TagLinksTableTableManager(_db, _db.tagLinks);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ExpenseCategoriesTableTableManager get expenseCategories =>
      $$ExpenseCategoriesTableTableManager(_db, _db.expenseCategories);
  $$GoalsTableTableManager get goals =>
      $$GoalsTableTableManager(_db, _db.goals);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$OpLogsTableTableManager get opLogs =>
      $$OpLogsTableTableManager(_db, _db.opLogs);
  $$MarketQuotesTableTableManager get marketQuotes =>
      $$MarketQuotesTableTableManager(_db, _db.marketQuotes);
  $$MarketHistoryBarsTableTableManager get marketHistoryBars =>
      $$MarketHistoryBarsTableTableManager(_db, _db.marketHistoryBars);
  $$MarketSymbolSearchesTableTableManager get marketSymbolSearches =>
      $$MarketSymbolSearchesTableTableManager(_db, _db.marketSymbolSearches);
  $$SecuritiesCatalogTableTableManager get securitiesCatalog =>
      $$SecuritiesCatalogTableTableManager(_db, _db.securitiesCatalog);
  $$SecuritiesCatalogMetaTableTableManager get securitiesCatalogMeta =>
      $$SecuritiesCatalogMetaTableTableManager(_db, _db.securitiesCatalogMeta);
  $$JournalEntriesTableTableManager get journalEntries =>
      $$JournalEntriesTableTableManager(_db, _db.journalEntries);
  $$PostingsTableTableManager get postings =>
      $$PostingsTableTableManager(_db, _db.postings);
  $$PricesTableTableManager get prices =>
      $$PricesTableTableManager(_db, _db.prices);
}
