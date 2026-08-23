import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/errors/user_safe_error.dart';
import '../../l10n/gen/app_localizations.dart';
import 'app_empty_state.dart';

/// Default loading widget: centred [FCircularProgress].
const Widget kDefaultLoading = Center(child: FCircularProgress());

/// Builds a default error widget from an [Object] error.
///
/// Renders an [AppEmptyState.error] with the error's [toString] as the
/// message and an optional [onRetry] callback surfaced as the canonical
/// primary retry action.
Widget kDefaultError(
  BuildContext context,
  Object error,
  StackTrace stackTrace, {
  VoidCallback? onRetry,
}) {
  final l10n = AppLocalizations.of(context);
  final message = userSafeErrorMessage(context, error, stackTrace: stackTrace);
  return AppEmptyState.error(
    title: l10n.commonLoadFailed,
    // The generic fallback sentence paraphrases the title ("couldn't load /
    // try again"); rendering both reads as the same message twice. Specific
    // `UserFacingError` copy still surfaces.
    message: message == l10n.commonSafeErrorMessage ? null : message,
    retryLabel: onRetry == null ? null : l10n.commonRetry,
    onRetry: onRetry,
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
    required BuildContext context,
    required Widget Function(T data) data,
    Widget Function()? loading,
    Widget Function(Object error, StackTrace stack)? error,
    VoidCallback? onRetry,
    bool skipLoadingOnRefresh = false,
    bool skipLoadingOnReload = false,
  }) {
    return when(
      loading: loading ?? () => kDefaultLoading,
      error:
          error ?? (e, st) => kDefaultError(context, e, st, onRetry: onRetry),
      data: data,
      skipLoadingOnRefresh: skipLoadingOnRefresh,
      skipLoadingOnReload: skipLoadingOnReload,
    );
  }

  /// Like [when], but supplies default loading AND error widgets.
  Widget whenOrError({
    required BuildContext context,
    required Widget Function(T data) data,
    Widget Function(Object error, StackTrace stack)? error,
    VoidCallback? onRetry,
  }) {
    return when(
      loading: () => kDefaultLoading,
      error:
          error ?? (e, st) => kDefaultError(context, e, st, onRetry: onRetry),
      data: data,
    );
  }
}
