import 'package:flutter/widgets.dart';
import 'package:talker/talker.dart';

/// Logs Flutter navigation events via [Talker].
class TalkerRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  TalkerRouteObserver(this._talker);

  final Talker _talker;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('pop', route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) return;
    _log('replace', newRoute, oldRoute);
  }

  void _log(String action, Route<dynamic> route, Route<dynamic>? previous) {
    final name = route.settings.name ?? 'unnamed';
    final from = previous?.settings.name ?? 'none';
    _talker.info('route $action: $name (from $from)');
  }
}
