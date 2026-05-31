import 'package:flutter/widgets.dart';
import '../design_system/design_system.dart';
import 'package:forui/forui.dart';
import '../design_system/design_system.dart';

import '../l10n/gen/app_localizations.dart';
import '../design_system/design_system.dart';

/// Wraps a route whose page widget lives in a `deferred as` library.
///
/// On first navigation the part file is fetched and parsed; subsequent visits
/// resolve synchronously because [Future] returned by `loadLibrary` caches.
/// A retry path is exposed so a transient network failure (offline, flaky
/// CDN) doesn't leave the user stuck on an error scaffold.
class DeferredRoute extends StatefulWidget {
  const DeferredRoute({
    super.key,
    required this.load,
    required this.builder,
    this.placeholder,
  });

  /// Typically `someLib.loadLibrary` — the function `dart:deferred` synthesizes.
  final Future<void> Function() load;

  /// Built only after [load] resolves successfully.
  final WidgetBuilder builder;

  /// Optional override for the in-flight indicator. Defaults to a centered
  /// progress ring inside a [Scaffold] so the bottom nav bar from the shell
  /// stays anchored.
  final Widget? placeholder;

  @override
  State<DeferredRoute> createState() => _DeferredRouteState();
}

class _DeferredRouteState extends State<DeferredRoute> {
  late Future<void> _future = widget.load();

  void _retry() {
    setState(() {
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder ?? const _DeferredLoading();
        }
        if (snapshot.hasError) {
          return _DeferredError(error: snapshot.error!, onRetry: _retry);
        }
        return widget.builder(context);
      },
    );
  }
}

class _DeferredLoading extends StatelessWidget {
  const _DeferredLoading();

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      childPad: false,
      child: Center(child: FCircularProgress()),
    );
  }
}

class _DeferredError extends StatelessWidget {
  const _DeferredError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      childPad: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FLucideIcons.cloudOff,
                size: 48,
                color: context.theme.colors.destructive,
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                l10n.deferredLoadFailedTitle,
                style: context.theme.typography.md,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                '$error',
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s16),
              FButton(
                variant: FButtonVariant.primary,
                onPress: onRetry,
                prefix: const Icon(FLucideIcons.refreshCw, size: 16),
                child: Text(l10n.deferredLoadRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
