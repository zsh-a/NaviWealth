import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/logging/providers.dart';

/// Hooks Flutter's [Navigator] lifecycle and emits a single `page_view` event
/// per route transition.
///
/// Currently events go through [AppLogger] (info-level) so they show up in
/// dev console + release breadcrumbs. Once the analytics SDK lands, swap the
/// `_PageViewSink` implementation registered in `pageViewSinkProvider` — the
/// observer itself doesn't need to change.
///
/// The observer is attached via `GoRouter(observers: [...])` in
/// `lib/app/router.dart` and is rebuilt whenever its sink changes (Riverpod
/// invalidation), so swapping the sink in tests is just an `overrideWithValue`.
class RouteAnalyticsObserver extends NavigatorObserver {
  RouteAnalyticsObserver(this._sink);

  final PageViewSink _sink;

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _emit(route, previousRoute, transition: 'push');
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    if (newRoute == null) return;
    _emit(newRoute, oldRoute, transition: 'replace');
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    // On pop, the *previous* route becomes visible again — that's the page
    // view we want to record. `route` is the one being torn down.
    if (previousRoute == null) return;
    _emit(previousRoute, route, transition: 'pop');
  }

  void _emit(
    Route<Object?> current,
    Route<Object?>? previous, {
    required String transition,
  }) {
    final name = _routeName(current);
    if (name == null) return; // Anonymous routes (dialogs, popups) — skip.
    _sink.recordPageView(
      PageViewEvent(
        name: name,
        previousName: previous == null ? null : _routeName(previous),
        transition: transition,
      ),
    );
  }

  static String? _routeName(Route<Object?> route) {
    final settings = route.settings;
    final name = settings.name;
    if (name == null || name.isEmpty) return null;
    return name;
  }
}

/// Single page-view payload. Kept tiny on purpose — we only persist what every
/// downstream sink (logger / Crashlytics / first-party analytics) can handle.
class PageViewEvent {
  const PageViewEvent({
    required this.name,
    required this.transition,
    this.previousName,
  });

  /// Route name from `GoRoute(name: ...)` or the page's `RouteSettings.name`.
  final String name;

  /// Previous route's name, if any. `null` on cold start.
  final String? previousName;

  /// `'push' | 'pop' | 'replace'`.
  final String transition;
}

/// Strategy for recording page views. Swap implementations via
/// [pageViewSinkProvider]; the observer stays the same.
abstract class PageViewSink {
  void recordPageView(PageViewEvent event);
}

/// Default sink: writes through [AppLogger] at info level. Once the analytics
/// SDK ships, override [pageViewSinkProvider] with a forwarding sink.
class LoggerPageViewSink implements PageViewSink {
  const LoggerPageViewSink(this._logger);

  final AppLogger _logger;

  @override
  void recordPageView(PageViewEvent event) {
    final from = event.previousName ?? '∅';
    _logger.i(
      'page_view ${event.transition} ${event.name} (from $from)',
    );
  }
}

final pageViewSinkProvider = Provider<PageViewSink>(
  (ref) => LoggerPageViewSink(ref.watch(loggerProvider)),
);

final routeAnalyticsObserverProvider = Provider<RouteAnalyticsObserver>(
  (ref) => RouteAnalyticsObserver(ref.watch(pageViewSinkProvider)),
);
