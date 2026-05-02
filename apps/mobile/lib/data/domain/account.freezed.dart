// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Account {

 String get id; AccountType get type; String get name; String get currency; String? get institution; String? get accountNumber; String? get note; bool get archived;/// FIR-126 — accounting classification of the account
/// (asset / liability / income / expense / equity). Defaults to
/// [AccountCategory.asset] for back-compat with code paths that still
/// construct an [Account] without a category; UI / repo callers
/// always supply an explicit value.
 AccountCategory get category;/// FIR-130 — Beancount-style account tree. NULL on top-level
/// accounts; on a child the parent's [id] forms the chain. The tree
/// is enforced as a parent / child relationship at the application
/// level (no DB constraint) so a sync-borne reorder doesn't fight
/// foreign-key checks during eventual-consistency replay.
 String? get parentId;/// FIR-130 — Material icon name driving the account's avatar in the
/// picker / list. Lifted off the legacy `expense_categories.icon`
/// surface so a single account-tree picker can render every category.
 String? get icon;/// FIR-130 — colour token for the account's avatar (hex or design
/// token id). Same provenance as [icon].
 String? get color; SyncMeta get sync;
/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCopyWith<Account> get copyWith => _$AccountCopyWithImpl<Account>(this as Account, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Account&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.name, name) || other.name == name)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.institution, institution) || other.institution == institution)&&(identical(other.accountNumber, accountNumber) || other.accountNumber == accountNumber)&&(identical(other.note, note) || other.note == note)&&(identical(other.archived, archived) || other.archived == archived)&&(identical(other.category, category) || other.category == category)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.icon, icon) || other.icon == icon)&&(identical(other.color, color) || other.color == color)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,name,currency,institution,accountNumber,note,archived,category,parentId,icon,color,sync);

@override
String toString() {
  return 'Account(id: $id, type: $type, name: $name, currency: $currency, institution: $institution, accountNumber: $accountNumber, note: $note, archived: $archived, category: $category, parentId: $parentId, icon: $icon, color: $color, sync: $sync)';
}


}

/// @nodoc
abstract mixin class $AccountCopyWith<$Res>  {
  factory $AccountCopyWith(Account value, $Res Function(Account) _then) = _$AccountCopyWithImpl;
@useResult
$Res call({
 String id, AccountType type, String name, String currency, String? institution, String? accountNumber, String? note, bool archived, AccountCategory category, String? parentId, String? icon, String? color, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$AccountCopyWithImpl<$Res>
    implements $AccountCopyWith<$Res> {
  _$AccountCopyWithImpl(this._self, this._then);

  final Account _self;
  final $Res Function(Account) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? name = null,Object? currency = null,Object? institution = freezed,Object? accountNumber = freezed,Object? note = freezed,Object? archived = null,Object? category = null,Object? parentId = freezed,Object? icon = freezed,Object? color = freezed,Object? sync = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AccountType,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,institution: freezed == institution ? _self.institution : institution // ignore: cast_nullable_to_non_nullable
as String?,accountNumber: freezed == accountNumber ? _self.accountNumber : accountNumber // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as AccountCategory,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,color: freezed == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [Account].
extension AccountPatterns on Account {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Account value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Account value)  $default,){
final _that = this;
switch (_that) {
case _Account():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Account value)?  $default,){
final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  AccountType type,  String name,  String currency,  String? institution,  String? accountNumber,  String? note,  bool archived,  AccountCategory category,  String? parentId,  String? icon,  String? color,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that.id,_that.type,_that.name,_that.currency,_that.institution,_that.accountNumber,_that.note,_that.archived,_that.category,_that.parentId,_that.icon,_that.color,_that.sync);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  AccountType type,  String name,  String currency,  String? institution,  String? accountNumber,  String? note,  bool archived,  AccountCategory category,  String? parentId,  String? icon,  String? color,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _Account():
return $default(_that.id,_that.type,_that.name,_that.currency,_that.institution,_that.accountNumber,_that.note,_that.archived,_that.category,_that.parentId,_that.icon,_that.color,_that.sync);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  AccountType type,  String name,  String currency,  String? institution,  String? accountNumber,  String? note,  bool archived,  AccountCategory category,  String? parentId,  String? icon,  String? color,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that.id,_that.type,_that.name,_that.currency,_that.institution,_that.accountNumber,_that.note,_that.archived,_that.category,_that.parentId,_that.icon,_that.color,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _Account implements Account {
  const _Account({required this.id, required this.type, required this.name, required this.currency, this.institution, this.accountNumber, this.note, this.archived = false, this.category = AccountCategory.asset, this.parentId, this.icon, this.color, required this.sync});
  

@override final  String id;
@override final  AccountType type;
@override final  String name;
@override final  String currency;
@override final  String? institution;
@override final  String? accountNumber;
@override final  String? note;
@override@JsonKey() final  bool archived;
/// FIR-126 — accounting classification of the account
/// (asset / liability / income / expense / equity). Defaults to
/// [AccountCategory.asset] for back-compat with code paths that still
/// construct an [Account] without a category; UI / repo callers
/// always supply an explicit value.
@override@JsonKey() final  AccountCategory category;
/// FIR-130 — Beancount-style account tree. NULL on top-level
/// accounts; on a child the parent's [id] forms the chain. The tree
/// is enforced as a parent / child relationship at the application
/// level (no DB constraint) so a sync-borne reorder doesn't fight
/// foreign-key checks during eventual-consistency replay.
@override final  String? parentId;
/// FIR-130 — Material icon name driving the account's avatar in the
/// picker / list. Lifted off the legacy `expense_categories.icon`
/// surface so a single account-tree picker can render every category.
@override final  String? icon;
/// FIR-130 — colour token for the account's avatar (hex or design
/// token id). Same provenance as [icon].
@override final  String? color;
@override final  SyncMeta sync;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountCopyWith<_Account> get copyWith => __$AccountCopyWithImpl<_Account>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Account&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.name, name) || other.name == name)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.institution, institution) || other.institution == institution)&&(identical(other.accountNumber, accountNumber) || other.accountNumber == accountNumber)&&(identical(other.note, note) || other.note == note)&&(identical(other.archived, archived) || other.archived == archived)&&(identical(other.category, category) || other.category == category)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.icon, icon) || other.icon == icon)&&(identical(other.color, color) || other.color == color)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,name,currency,institution,accountNumber,note,archived,category,parentId,icon,color,sync);

@override
String toString() {
  return 'Account(id: $id, type: $type, name: $name, currency: $currency, institution: $institution, accountNumber: $accountNumber, note: $note, archived: $archived, category: $category, parentId: $parentId, icon: $icon, color: $color, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$AccountCopyWith<$Res> implements $AccountCopyWith<$Res> {
  factory _$AccountCopyWith(_Account value, $Res Function(_Account) _then) = __$AccountCopyWithImpl;
@override @useResult
$Res call({
 String id, AccountType type, String name, String currency, String? institution, String? accountNumber, String? note, bool archived, AccountCategory category, String? parentId, String? icon, String? color, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$AccountCopyWithImpl<$Res>
    implements _$AccountCopyWith<$Res> {
  __$AccountCopyWithImpl(this._self, this._then);

  final _Account _self;
  final $Res Function(_Account) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? name = null,Object? currency = null,Object? institution = freezed,Object? accountNumber = freezed,Object? note = freezed,Object? archived = null,Object? category = null,Object? parentId = freezed,Object? icon = freezed,Object? color = freezed,Object? sync = null,}) {
  return _then(_Account(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AccountType,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,institution: freezed == institution ? _self.institution : institution // ignore: cast_nullable_to_non_nullable
as String?,accountNumber: freezed == accountNumber ? _self.accountNumber : accountNumber // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as AccountCategory,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,color: freezed == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}

// dart format on
