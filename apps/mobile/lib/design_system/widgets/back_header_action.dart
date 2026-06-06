import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../tokens/dimens_tokens.dart';
import 'back_navigation.dart';

/// Standard back action for [FHeader.nested.prefixes].
///
/// Use this directly only when you also need to add other prefixes
/// alongside the back arrow. For the common case (sub-page = back +
/// optional suffixes), prefer [appSubPageHeader] — it injects this
/// automatically so a forgotten back arrow becomes impossible.
///
/// Top-level tab pages (Today / Activity / Wealth / Plan) MUST NOT use
/// this — they have nothing to go back to and the bottom nav handles
/// tab switching.
///
/// Pass [confirmLeave] on forms that hold unsaved input: it runs before
/// the pop and, when it resolves `false`, the back is cancelled (the
/// user chose to keep editing). See `FormDirtyGuard`.
FHeaderAction backHeaderAction(
  BuildContext context, {
  Future<bool> Function()? confirmLeave,
}) {
  return FHeaderAction(
    icon: const Icon(
      FLucideIcons.arrowLeft,
      key: ValueKey('app.back'),
      size: 18,
    ),
    semanticsLabel: AppLocalizations.of(context).routeGoBack,
    onPress: () async {
      if (confirmLeave != null) {
        final mayLeave = await confirmLeave();
        if (!mayLeave) return;
      }
      if (context.mounted) smartPop(context);
    },
  );
}

/// Builds an [FHeader.nested] for a pushed sub-page, with the standard
/// back arrow prepended automatically. The single source of truth for
/// "this page has a back button".
///
/// **Use this on every non-tab page that has a header.** Tab pages
/// (Today / Activity / Wealth / Plan) must use [FHeader.nested]
/// directly so they don't render a back arrow.
///
/// The `tool/check-back-nav-coverage.sh` CI guard enforces this rule:
/// any `FHeader.nested(` outside the tab-page allowlist that also
/// doesn't reference [appSubPageHeader] or [backHeaderAction] fails CI.
///
/// Example:
/// ```dart
/// FScaffold(
///   header: appSubPageHeader(
///     context: context,
///     title: Text(l10n.settingsAppBarTitle),
///     suffixes: [FHeaderAction(icon: ..., onPress: ...)],
///   ),
///   child: ...,
/// )
/// ```
FHeader appSubPageHeader({
  required BuildContext context,
  required Widget title,
  List<Widget> suffixes = const [],
  Future<bool> Function()? confirmLeave,
}) {
  return FHeader.nested(
    title: _AppHeaderTitle(title),
    prefixes: [backHeaderAction(context, confirmLeave: confirmLeave)],
    suffixes: suffixes,
  );
}

class _AppHeaderTitle extends StatelessWidget {
  const _AppHeaderTitle(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return DefaultTextStyle.merge(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: typography.lg.copyWith(
        color: colors.foreground,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
        child: child,
      ),
    );
  }
}
