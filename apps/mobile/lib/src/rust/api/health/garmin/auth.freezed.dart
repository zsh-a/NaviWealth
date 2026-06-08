// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AuthResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthResult()';
}


}

/// @nodoc
class $AuthResultCopyWith<$Res>  {
$AuthResultCopyWith(AuthResult _, $Res Function(AuthResult) __);
}


/// Adds pattern-matching-related methods to [AuthResult].
extension AuthResultPatterns on AuthResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AuthResult_Authenticated value)?  authenticated,TResult Function( AuthResult_MfaRequired value)?  mfaRequired,TResult Function( AuthResult_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AuthResult_Authenticated() when authenticated != null:
return authenticated(_that);case AuthResult_MfaRequired() when mfaRequired != null:
return mfaRequired(_that);case AuthResult_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AuthResult_Authenticated value)  authenticated,required TResult Function( AuthResult_MfaRequired value)  mfaRequired,required TResult Function( AuthResult_Failed value)  failed,}){
final _that = this;
switch (_that) {
case AuthResult_Authenticated():
return authenticated(_that);case AuthResult_MfaRequired():
return mfaRequired(_that);case AuthResult_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AuthResult_Authenticated value)?  authenticated,TResult? Function( AuthResult_MfaRequired value)?  mfaRequired,TResult? Function( AuthResult_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case AuthResult_Authenticated() when authenticated != null:
return authenticated(_that);case AuthResult_MfaRequired() when mfaRequired != null:
return mfaRequired(_that);case AuthResult_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  authenticated,TResult Function()?  mfaRequired,TResult Function( String field0)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AuthResult_Authenticated() when authenticated != null:
return authenticated();case AuthResult_MfaRequired() when mfaRequired != null:
return mfaRequired();case AuthResult_Failed() when failed != null:
return failed(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  authenticated,required TResult Function()  mfaRequired,required TResult Function( String field0)  failed,}) {final _that = this;
switch (_that) {
case AuthResult_Authenticated():
return authenticated();case AuthResult_MfaRequired():
return mfaRequired();case AuthResult_Failed():
return failed(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  authenticated,TResult? Function()?  mfaRequired,TResult? Function( String field0)?  failed,}) {final _that = this;
switch (_that) {
case AuthResult_Authenticated() when authenticated != null:
return authenticated();case AuthResult_MfaRequired() when mfaRequired != null:
return mfaRequired();case AuthResult_Failed() when failed != null:
return failed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class AuthResult_Authenticated extends AuthResult {
  const AuthResult_Authenticated(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthResult_Authenticated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthResult.authenticated()';
}


}




/// @nodoc


class AuthResult_MfaRequired extends AuthResult {
  const AuthResult_MfaRequired(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthResult_MfaRequired);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthResult.mfaRequired()';
}


}




/// @nodoc


class AuthResult_Failed extends AuthResult {
  const AuthResult_Failed(this.field0): super._();
  

 final  String field0;

/// Create a copy of AuthResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthResult_FailedCopyWith<AuthResult_Failed> get copyWith => _$AuthResult_FailedCopyWithImpl<AuthResult_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthResult_Failed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AuthResult.failed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AuthResult_FailedCopyWith<$Res> implements $AuthResultCopyWith<$Res> {
  factory $AuthResult_FailedCopyWith(AuthResult_Failed value, $Res Function(AuthResult_Failed) _then) = _$AuthResult_FailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AuthResult_FailedCopyWithImpl<$Res>
    implements $AuthResult_FailedCopyWith<$Res> {
  _$AuthResult_FailedCopyWithImpl(this._self, this._then);

  final AuthResult_Failed _self;
  final $Res Function(AuthResult_Failed) _then;

/// Create a copy of AuthResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AuthResult_Failed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$GarminAuthState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GarminAuthState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GarminAuthState()';
}


}

/// @nodoc
class $GarminAuthStateCopyWith<$Res>  {
$GarminAuthStateCopyWith(GarminAuthState _, $Res Function(GarminAuthState) __);
}


/// Adds pattern-matching-related methods to [GarminAuthState].
extension GarminAuthStatePatterns on GarminAuthState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GarminAuthState_Unauthenticated value)?  unauthenticated,TResult Function( GarminAuthState_PendingMfa value)?  pendingMfa,TResult Function( GarminAuthState_Authenticated value)?  authenticated,TResult Function( GarminAuthState_Refreshing value)?  refreshing,TResult Function( GarminAuthState_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GarminAuthState_Unauthenticated() when unauthenticated != null:
return unauthenticated(_that);case GarminAuthState_PendingMfa() when pendingMfa != null:
return pendingMfa(_that);case GarminAuthState_Authenticated() when authenticated != null:
return authenticated(_that);case GarminAuthState_Refreshing() when refreshing != null:
return refreshing(_that);case GarminAuthState_Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GarminAuthState_Unauthenticated value)  unauthenticated,required TResult Function( GarminAuthState_PendingMfa value)  pendingMfa,required TResult Function( GarminAuthState_Authenticated value)  authenticated,required TResult Function( GarminAuthState_Refreshing value)  refreshing,required TResult Function( GarminAuthState_Error value)  error,}){
final _that = this;
switch (_that) {
case GarminAuthState_Unauthenticated():
return unauthenticated(_that);case GarminAuthState_PendingMfa():
return pendingMfa(_that);case GarminAuthState_Authenticated():
return authenticated(_that);case GarminAuthState_Refreshing():
return refreshing(_that);case GarminAuthState_Error():
return error(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GarminAuthState_Unauthenticated value)?  unauthenticated,TResult? Function( GarminAuthState_PendingMfa value)?  pendingMfa,TResult? Function( GarminAuthState_Authenticated value)?  authenticated,TResult? Function( GarminAuthState_Refreshing value)?  refreshing,TResult? Function( GarminAuthState_Error value)?  error,}){
final _that = this;
switch (_that) {
case GarminAuthState_Unauthenticated() when unauthenticated != null:
return unauthenticated(_that);case GarminAuthState_PendingMfa() when pendingMfa != null:
return pendingMfa(_that);case GarminAuthState_Authenticated() when authenticated != null:
return authenticated(_that);case GarminAuthState_Refreshing() when refreshing != null:
return refreshing(_that);case GarminAuthState_Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unauthenticated,TResult Function( String sessionTicket)?  pendingMfa,TResult Function( DateTime expiresAt)?  authenticated,TResult Function()?  refreshing,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GarminAuthState_Unauthenticated() when unauthenticated != null:
return unauthenticated();case GarminAuthState_PendingMfa() when pendingMfa != null:
return pendingMfa(_that.sessionTicket);case GarminAuthState_Authenticated() when authenticated != null:
return authenticated(_that.expiresAt);case GarminAuthState_Refreshing() when refreshing != null:
return refreshing();case GarminAuthState_Error() when error != null:
return error(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unauthenticated,required TResult Function( String sessionTicket)  pendingMfa,required TResult Function( DateTime expiresAt)  authenticated,required TResult Function()  refreshing,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case GarminAuthState_Unauthenticated():
return unauthenticated();case GarminAuthState_PendingMfa():
return pendingMfa(_that.sessionTicket);case GarminAuthState_Authenticated():
return authenticated(_that.expiresAt);case GarminAuthState_Refreshing():
return refreshing();case GarminAuthState_Error():
return error(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unauthenticated,TResult? Function( String sessionTicket)?  pendingMfa,TResult? Function( DateTime expiresAt)?  authenticated,TResult? Function()?  refreshing,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case GarminAuthState_Unauthenticated() when unauthenticated != null:
return unauthenticated();case GarminAuthState_PendingMfa() when pendingMfa != null:
return pendingMfa(_that.sessionTicket);case GarminAuthState_Authenticated() when authenticated != null:
return authenticated(_that.expiresAt);case GarminAuthState_Refreshing() when refreshing != null:
return refreshing();case GarminAuthState_Error() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class GarminAuthState_Unauthenticated extends GarminAuthState {
  const GarminAuthState_Unauthenticated(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GarminAuthState_Unauthenticated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GarminAuthState.unauthenticated()';
}


}




/// @nodoc


class GarminAuthState_PendingMfa extends GarminAuthState {
  const GarminAuthState_PendingMfa({required this.sessionTicket}): super._();
  

/// Opaque session ticket from the SSO flow.
 final  String sessionTicket;

/// Create a copy of GarminAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GarminAuthState_PendingMfaCopyWith<GarminAuthState_PendingMfa> get copyWith => _$GarminAuthState_PendingMfaCopyWithImpl<GarminAuthState_PendingMfa>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GarminAuthState_PendingMfa&&(identical(other.sessionTicket, sessionTicket) || other.sessionTicket == sessionTicket));
}


@override
int get hashCode => Object.hash(runtimeType,sessionTicket);

@override
String toString() {
  return 'GarminAuthState.pendingMfa(sessionTicket: $sessionTicket)';
}


}

/// @nodoc
abstract mixin class $GarminAuthState_PendingMfaCopyWith<$Res> implements $GarminAuthStateCopyWith<$Res> {
  factory $GarminAuthState_PendingMfaCopyWith(GarminAuthState_PendingMfa value, $Res Function(GarminAuthState_PendingMfa) _then) = _$GarminAuthState_PendingMfaCopyWithImpl;
@useResult
$Res call({
 String sessionTicket
});




}
/// @nodoc
class _$GarminAuthState_PendingMfaCopyWithImpl<$Res>
    implements $GarminAuthState_PendingMfaCopyWith<$Res> {
  _$GarminAuthState_PendingMfaCopyWithImpl(this._self, this._then);

  final GarminAuthState_PendingMfa _self;
  final $Res Function(GarminAuthState_PendingMfa) _then;

/// Create a copy of GarminAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionTicket = null,}) {
  return _then(GarminAuthState_PendingMfa(
sessionTicket: null == sessionTicket ? _self.sessionTicket : sessionTicket // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class GarminAuthState_Authenticated extends GarminAuthState {
  const GarminAuthState_Authenticated({required this.expiresAt}): super._();
  

 final  DateTime expiresAt;

/// Create a copy of GarminAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GarminAuthState_AuthenticatedCopyWith<GarminAuthState_Authenticated> get copyWith => _$GarminAuthState_AuthenticatedCopyWithImpl<GarminAuthState_Authenticated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GarminAuthState_Authenticated&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt));
}


@override
int get hashCode => Object.hash(runtimeType,expiresAt);

@override
String toString() {
  return 'GarminAuthState.authenticated(expiresAt: $expiresAt)';
}


}

/// @nodoc
abstract mixin class $GarminAuthState_AuthenticatedCopyWith<$Res> implements $GarminAuthStateCopyWith<$Res> {
  factory $GarminAuthState_AuthenticatedCopyWith(GarminAuthState_Authenticated value, $Res Function(GarminAuthState_Authenticated) _then) = _$GarminAuthState_AuthenticatedCopyWithImpl;
@useResult
$Res call({
 DateTime expiresAt
});




}
/// @nodoc
class _$GarminAuthState_AuthenticatedCopyWithImpl<$Res>
    implements $GarminAuthState_AuthenticatedCopyWith<$Res> {
  _$GarminAuthState_AuthenticatedCopyWithImpl(this._self, this._then);

  final GarminAuthState_Authenticated _self;
  final $Res Function(GarminAuthState_Authenticated) _then;

/// Create a copy of GarminAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? expiresAt = null,}) {
  return _then(GarminAuthState_Authenticated(
expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc


class GarminAuthState_Refreshing extends GarminAuthState {
  const GarminAuthState_Refreshing(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GarminAuthState_Refreshing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GarminAuthState.refreshing()';
}


}




/// @nodoc


class GarminAuthState_Error extends GarminAuthState {
  const GarminAuthState_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of GarminAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GarminAuthState_ErrorCopyWith<GarminAuthState_Error> get copyWith => _$GarminAuthState_ErrorCopyWithImpl<GarminAuthState_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GarminAuthState_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'GarminAuthState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $GarminAuthState_ErrorCopyWith<$Res> implements $GarminAuthStateCopyWith<$Res> {
  factory $GarminAuthState_ErrorCopyWith(GarminAuthState_Error value, $Res Function(GarminAuthState_Error) _then) = _$GarminAuthState_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$GarminAuthState_ErrorCopyWithImpl<$Res>
    implements $GarminAuthState_ErrorCopyWith<$Res> {
  _$GarminAuthState_ErrorCopyWithImpl(this._self, this._then);

  final GarminAuthState_Error _self;
  final $Res Function(GarminAuthState_Error) _then;

/// Create a copy of GarminAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(GarminAuthState_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
