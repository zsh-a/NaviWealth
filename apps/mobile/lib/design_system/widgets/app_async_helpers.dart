import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'app_empty_state.dart';

/// Default loading widget: centred [FCircularProgress].
const Widget kDefaultLoading = Center(child: FCircularProgress());

/// Builds a default error widget from an [Object] error.
///
/// Renders an [AppEmptyState.error] with the error's [toString] as the
/// message and an optional [onRetry] callback surfaced as a ghost button.
Widget kDefaultError(Object error, _, {VoidCallback? onRetry}) {
  return AppEmptyState.error(
    title: 'Something went wrong',
    message: '$error',
    action: onRetry != null
        ? FButton(
            variant: FButtonVariant.ghost,
            onPress: onRetry,
            child: const Text('Retry'),
          )
        : null,
  );
}

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
    VoidCallback? onRetry,
    bool skipLoadingOnRefresh = false,
    bool skipLoadingOnReload = false,
  }) {
    return when(
      loading: () => kDefaultLoading,
      error: error ?? (e, st) => kDefaultError(e, st, onRetry: onRetry),
      data: data,
      skipLoadingOnRefresh: skipLoadingOnRefresh,
      skipLoadingOnReload: skipLoadingOnReload,
    );
  }

  /// Like [when], but supplies default loading AND error widgets.
  Widget whenOrError({
    required Widget Function(T data) data,
    Widget Function(Object error, StackTrace stack)? error,
    VoidCallback? onRetry,
  }) {
    return when(
      loading: () => kDefaultLoading,
      error: error ?? (e, st) => kDefaultError(e, st, onRetry: onRetry),
      data: data,
    );
  }
}
