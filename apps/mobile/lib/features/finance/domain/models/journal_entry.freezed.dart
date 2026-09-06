// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'journal_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JournalEntry {

 String get id;/// Trade date — when the economic event happened. Drives the natural
/// ordering of the ledger and, together with [settledOn], lets reports
/// distinguish "the trade" from "the cash settling".
 DateTime get date;/// Settlement date. NULL means same-day (most cash flows / transfers);
/// the typical non-NULL case is broker T+2 settlement on a trade.
 DateTime? get settledOn;/// Free-form description (`"Buy AAPL"`, `"Salary"`, `"Coffee at the
/// office"`). Required and non-empty by convention so the timeline
/// view always has something to render even before a user customises
/// the entry.
 String get narration;/// Optional counter-party. Used by reports that want to slice spend
/// by merchant ("Costco", "Walmart") or income by source.
 String? get payee; List<String> get tagIds; EntryFlag get flag; SyncMeta get sync;
/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JournalEntryCopyWith<JournalEntry> get copyWith => _$JournalEntryCopyWithImpl<JournalEntry>(this as JournalEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as JournalEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JournalEntry&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.date, _this.date) || other.date == _this.date)&&(identical(other.settledOn, _this.settledOn) || other.settledOn == _this.settledOn)&&(identical(other.narration, _this.narration) || other.narration == _this.narration)&&(identical(other.payee, _this.payee) || other.payee == _this.payee)&&const DeepCollectionEquality().equals(other.tagIds, _this.tagIds)&&(identical(other.flag, _this.flag) || other.flag == _this.flag)&&(identical(other.sync, _this.sync) || other.sync == _this.sync));
}


@override
int get hashCode {
  final _this = this as JournalEntry;
  return Object.hash(runtimeType,_this.id,_this.date,_this.settledOn,_this.narration,_this.payee,const DeepCollectionEquality().hash(_this.tagIds),_this.flag,_this.sync);
}

@override
String toString() {
  final _this = this as JournalEntry;
  return 'JournalEntry(id: ${_this.id}, date: ${_this.date}, settledOn: ${_this.settledOn}, narration: ${_this.narration}, payee: ${_this.payee}, tagIds: ${_this.tagIds}, flag: ${_this.flag}, sync: ${_this.sync})';
}


}

/// @nodoc
abstract mixin class $JournalEntryCopyWith<$Res>  {
  factory $JournalEntryCopyWith(JournalEntry value, $Res Function(JournalEntry) _then) = _$JournalEntryCopyWithImpl;
@useResult
$Res call({
 String id, DateTime date, DateTime? settledOn, String narration, String? payee, List<String> tagIds, EntryFlag flag, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$JournalEntryCopyWithImpl<$Res>
    implements $JournalEntryCopyWith<$Res> {
  _$JournalEntryCopyWithImpl(this._self, this._then);

  final JournalEntry _self;
  final $Res Function(JournalEntry) _then;

/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? date = null,Object? settledOn = freezed,Object? narration = null,Object? payee = freezed,Object? tagIds = null,Object? flag = null,Object? sync = null,}) {
  return _then(JournalEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,settledOn: freezed == settledOn ? _self.settledOn : settledOn // ignore: cast_nullable_to_non_nullable
as DateTime?,narration: null == narration ? _self.narration : narration // ignore: cast_nullable_to_non_nullable
as String,payee: freezed == payee ? _self.payee : payee // ignore: cast_nullable_to_non_nullable
as String?,tagIds: null == tagIds ? _self.tagIds : tagIds // ignore: cast_nullable_to_non_nullable
as List<String>,flag: null == flag ? _self.flag : flag // ignore: cast_nullable_to_non_nullable
as EntryFlag,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [JournalEntry].
extension JournalEntryPatterns on JournalEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JournalEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JournalEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JournalEntry value)  $default,){
final _that = this;
switch (_that) {
case _JournalEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JournalEntry value)?  $default,){
final _that = this;
switch (_that) {
case _JournalEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime date,  DateTime? settledOn,  String narration,  String? payee,  List<String> tagIds,  EntryFlag flag,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JournalEntry() when $default != null:
return $default(_that.id,_that.date,_that.settledOn,_that.narration,_that.payee,_that.tagIds,_that.flag,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime date,  DateTime? settledOn,  String narration,  String? payee,  List<String> tagIds,  EntryFlag flag,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _JournalEntry():
return $default(_that.id,_that.date,_that.settledOn,_that.narration,_that.payee,_that.tagIds,_that.flag,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime date,  DateTime? settledOn,  String narration,  String? payee,  List<String> tagIds,  EntryFlag flag,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _JournalEntry() when $default != null:
return $default(_that.id,_that.date,_that.settledOn,_that.narration,_that.payee,_that.tagIds,_that.flag,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _JournalEntry implements JournalEntry {
  const _JournalEntry({required this.id, required this.date, this.settledOn, required this.narration, this.payee,  List<String> tagIds = const <String>[], this.flag = EntryFlag.confirmed, required this.sync}): _tagIds = tagIds;
  

@override final  String id;
/// Trade date — when the economic event happened. Drives the natural
/// ordering of the ledger and, together with [settledOn], lets reports
/// distinguish "the trade" from "the cash settling".
@override final  DateTime date;
/// Settlement date. NULL means same-day (most cash flows / transfers);
/// the typical non-NULL case is broker T+2 settlement on a trade.
@override final  DateTime? settledOn;
/// Free-form description (`"Buy AAPL"`, `"Salary"`, `"Coffee at the
/// office"`). Required and non-empty by convention so the timeline
/// view always has something to render even before a user customises
/// the entry.
@override final  String narration;
/// Optional counter-party. Used by reports that want to slice spend
/// by merchant ("Costco", "Walmart") or income by source.
@override final  String? payee;
 final  List<String> _tagIds;
@override@JsonKey() List<String> get tagIds {
  if (_tagIds is EqualUnmodifiableListView) return _tagIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tagIds);
}

@override@JsonKey() final  EntryFlag flag;
@override final  SyncMeta sync;

/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JournalEntryCopyWith<_JournalEntry> get copyWith => __$JournalEntryCopyWithImpl<_JournalEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _JournalEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.date, date) || other.date == date)&&(identical(other.settledOn, settledOn) || other.settledOn == settledOn)&&(identical(other.narration, narration) || other.narration == narration)&&(identical(other.payee, payee) || other.payee == payee)&&const DeepCollectionEquality().equals(other.tagIds, _tagIds)&&(identical(other.flag, flag) || other.flag == flag)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,date,settledOn,narration,payee,const DeepCollectionEquality().hash(_tagIds),flag,sync);
}

@override
String toString() {
    return 'JournalEntry(id: $id, date: $date, settledOn: $settledOn, narration: $narration, payee: $payee, tagIds: $tagIds, flag: $flag, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$JournalEntryCopyWith<$Res> implements $JournalEntryCopyWith<$Res> {
  factory _$JournalEntryCopyWith(_JournalEntry value, $Res Function(_JournalEntry) _then) = __$JournalEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime date, DateTime? settledOn, String narration, String? payee, List<String> tagIds, EntryFlag flag, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$JournalEntryCopyWithImpl<$Res>
    implements _$JournalEntryCopyWith<$Res> {
  __$JournalEntryCopyWithImpl(this._self, this._then);

  final _JournalEntry _self;
  final $Res Function(_JournalEntry) _then;

/// Create a copy of JournalEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? date = null,Object? settledOn = freezed,Object? narration = null,Object? payee = freezed,Object? tagIds = null,Object? flag = null,Object? sync = null,}) {
  return _then(_JournalEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,settledOn: freezed == settledOn ? _self.settledOn : settledOn // ignore: cast_nullable_to_non_nullable
as DateTime?,narration: null == narration ? _self.narration : narration // ignore: cast_nullable_to_non_nullable
as String,payee: freezed == payee ? _self.payee : payee // ignore: cast_nullable_to_non_nullable
as String?,tagIds: null == tagIds ? _self._tagIds : tagIds // ignore: cast_nullable_to_non_nullable
as List<String>,flag: null == flag ? _self.flag : flag // ignore: cast_nullable_to_non_nullable
as EntryFlag,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of JournalEntry
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
