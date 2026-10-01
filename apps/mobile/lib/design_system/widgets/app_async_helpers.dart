import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/user_safe_error.dart';
import '../../l10n/gen/app_localizations.dart';
import '../tokens/dimens_tokens.dart';
import 'app_empty_state.dart';
import 'skeleton.dart';

/// Compact content placeholder; action buttons own their progress spinners.
const Widget kDefaultLoading = Padding(
  padding: EdgeInsets.all(AppSpacing.s16),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SkeletonBox(height: 16),
      SizedBox(height: AppSpacing.s12),
      SkeletonBox(height: 16),
      SizedBox(height: AppSpacing.s12),
      SkeletonBox(height: 16),
    ],
  ),
);

/// Builds a default error widget from an [Object] error.
///
/// Renders an [AppEmptyState.error] with a user-safe message and an
/// optional [onRetry] callback surfaced as the canonical
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
  /// Like [when], but preserves resolved content during refresh by default.
  Widget whenOrLoading({
    required BuildContext context,
    required Widget Function(T data) data,
    Widget Function()? loading,
    Widget Function(Object error, StackTrace stack)? error,
    VoidCallback? onRetry,
    bool skipLoadingOnRefresh = true,
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
