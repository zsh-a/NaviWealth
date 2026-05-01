// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'expense_category.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ExpenseCategory {

 String get id; String get name; String? get parentId; String? get icon; String? get color; int? get sortOrder; DateTime? get archivedAt; SyncMeta get sync;
/// Create a copy of ExpenseCategory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExpenseCategoryCopyWith<ExpenseCategory> get copyWith => _$ExpenseCategoryCopyWithImpl<ExpenseCategory>(this as ExpenseCategory, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExpenseCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.icon, icon) || other.icon == icon)&&(identical(other.color, color) || other.color == color)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.archivedAt, archivedAt) || other.archivedAt == archivedAt)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,parentId,icon,color,sortOrder,archivedAt,sync);

@override
String toString() {
  return 'ExpenseCategory(id: $id, name: $name, parentId: $parentId, icon: $icon, color: $color, sortOrder: $sortOrder, archivedAt: $archivedAt, sync: $sync)';
}


}

/// @nodoc
abstract mixin class $ExpenseCategoryCopyWith<$Res>  {
  factory $ExpenseCategoryCopyWith(ExpenseCategory value, $Res Function(ExpenseCategory) _then) = _$ExpenseCategoryCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? parentId, String? icon, String? color, int? sortOrder, DateTime? archivedAt, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$ExpenseCategoryCopyWithImpl<$Res>
    implements $ExpenseCategoryCopyWith<$Res> {
  _$ExpenseCategoryCopyWithImpl(this._self, this._then);

  final ExpenseCategory _self;
  final $Res Function(ExpenseCategory) _then;

/// Create a copy of ExpenseCategory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? parentId = freezed,Object? icon = freezed,Object? color = freezed,Object? sortOrder = freezed,Object? archivedAt = freezed,Object? sync = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,color: freezed == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String?,sortOrder: freezed == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int?,archivedAt: freezed == archivedAt ? _self.archivedAt : archivedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of ExpenseCategory
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [ExpenseCategory].
extension ExpenseCategoryPatterns on ExpenseCategory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExpenseCategory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExpenseCategory() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExpenseCategory value)  $default,){
final _that = this;
switch (_that) {
case _ExpenseCategory():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExpenseCategory value)?  $default,){
final _that = this;
switch (_that) {
case _ExpenseCategory() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? parentId,  String? icon,  String? color,  int? sortOrder,  DateTime? archivedAt,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExpenseCategory() when $default != null:
return $default(_that.id,_that.name,_that.parentId,_that.icon,_that.color,_that.sortOrder,_that.archivedAt,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? parentId,  String? icon,  String? color,  int? sortOrder,  DateTime? archivedAt,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _ExpenseCategory():
return $default(_that.id,_that.name,_that.parentId,_that.icon,_that.color,_that.sortOrder,_that.archivedAt,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? parentId,  String? icon,  String? color,  int? sortOrder,  DateTime? archivedAt,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _ExpenseCategory() when $default != null:
return $default(_that.id,_that.name,_that.parentId,_that.icon,_that.color,_that.sortOrder,_that.archivedAt,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _ExpenseCategory implements ExpenseCategory {
  const _ExpenseCategory({required this.id, required this.name, this.parentId, this.icon, this.color, this.sortOrder, this.archivedAt, required this.sync});
  

@override final  String id;
@override final  String name;
@override final  String? parentId;
@override final  String? icon;
@override final  String? color;
@override final  int? sortOrder;
@override final  DateTime? archivedAt;
@override final  SyncMeta sync;

/// Create a copy of ExpenseCategory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExpenseCategoryCopyWith<_ExpenseCategory> get copyWith => __$ExpenseCategoryCopyWithImpl<_ExpenseCategory>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExpenseCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.icon, icon) || other.icon == icon)&&(identical(other.color, color) || other.color == color)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.archivedAt, archivedAt) || other.archivedAt == archivedAt)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,parentId,icon,color,sortOrder,archivedAt,sync);

@override
String toString() {
  return 'ExpenseCategory(id: $id, name: $name, parentId: $parentId, icon: $icon, color: $color, sortOrder: $sortOrder, archivedAt: $archivedAt, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$ExpenseCategoryCopyWith<$Res> implements $ExpenseCategoryCopyWith<$Res> {
  factory _$ExpenseCategoryCopyWith(_ExpenseCategory value, $Res Function(_ExpenseCategory) _then) = __$ExpenseCategoryCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? parentId, String? icon, String? color, int? sortOrder, DateTime? archivedAt, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$ExpenseCategoryCopyWithImpl<$Res>
    implements _$ExpenseCategoryCopyWith<$Res> {
  __$ExpenseCategoryCopyWithImpl(this._self, this._then);

  final _ExpenseCategory _self;
  final $Res Function(_ExpenseCategory) _then;

/// Create a copy of ExpenseCategory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? parentId = freezed,Object? icon = freezed,Object? color = freezed,Object? sortOrder = freezed,Object? archivedAt = freezed,Object? sync = null,}) {
  return _then(_ExpenseCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,color: freezed == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String?,sortOrder: freezed == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int?,archivedAt: freezed == archivedAt ? _self.archivedAt : archivedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of ExpenseCategory
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
