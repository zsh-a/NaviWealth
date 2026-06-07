import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

/// Default loading widget: centred [FCircularProgress].
const Widget kDefaultLoading = Center(child: FCircularProgress());

/// Builds a default error widget from an [Object] error.
Widget kDefaultError(Object error, _) => Center(child: Text('$error'));

/// Convenience extensions on [AsyncValue] that supply standard
/// loading / error widgets so feature pages don't copy-paste the
/// same lambdas 28+ times.
///
/// Usage:
/// ```dart
/// async.whenOrLoading(data: (items) => _buildList(items))
/// async.whenOrError(data: (items) => _buildList(items))
/// ```
extension AsyncValueWhenX<T> on AsyncValue<T> {
  /// Like [when], but supplies a default [FCircularProgress] for loading.
  Widget whenOrLoading({
    required Widget Function(T data) data,
    Widget Function(Object error, StackTrace stack)? error,
    bool skipLoadingOnRefresh = false,
    bool skipLoadingOnReload = false,
  }) {
    return when(
      loading: () => kDefaultLoading,
      error: error ?? kDefaultError,
      data: data,
      skipLoadingOnRefresh: skipLoadingOnRefresh,
      skipLoadingOnReload: skipLoadingOnReload,
    );
  }

  /// Like [when], but supplies default loading AND error widgets.
  Widget whenOrError({
    required Widget Function(T data) data,
    Widget Function(Object error, StackTrace stack)? error,
  }) {
    return when(
      loading: () => kDefaultLoading,
      error: error ?? kDefaultError,
      data: data,
    );
  }
}
