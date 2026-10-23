import 'package:go_router/go_router.dart';

/// The rendered route after redirects and imperative page pushes.
///
/// RouteInformationProvider can still hold the requested pre-redirect URL when
/// the delegate notifies shell consumers. Derive chrome and context from the
/// same matched configuration that renders the page.
String activeRoutePath(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  if (configuration.isEmpty) {
    return router.routeInformationProvider.value.uri.path;
  }
  final last = configuration.last;
  return last is ImperativeRouteMatch
      ? last.matches.uri.path
      : configuration.uri.path;
}
