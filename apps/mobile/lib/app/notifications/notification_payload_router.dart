import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/notifications/providers.dart';

/// App-level bridge from notification tap payloads to internal routes.
///
/// Core notification transport stays domain-neutral; domains only mint route
/// payloads. This listener consumes those payloads once the app has a router.
class NotificationPayloadRouteListener extends ConsumerStatefulWidget {
  const NotificationPayloadRouteListener({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<NotificationPayloadRouteListener> createState() =>
      _NotificationPayloadRouteListenerState();
}

class _NotificationPayloadRouteListenerState
    extends ConsumerState<NotificationPayloadRouteListener> {
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    final service = ref.read(notificationServiceProvider);
    _subscription = service.payloads.listen(_handlePayload);
    unawaited(_handleInitialPayload(service));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _handleInitialPayload(NotificationService service) async {
    try {
      final payload = await service.initialPayload();
      if (!mounted) return;
      _handlePayload(payload);
    } on Object {
      // Best-effort: notification tap routing must not block app bootstrap.
    }
  }

  void _handlePayload(String? payload) {
    final route = notificationRouteFromPayload(payload);
    if (route == null) return;
    widget.router.go(route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String? notificationRouteFromPayload(String? payload) {
  final value = payload?.trim();
  if (value == null || value.isEmpty || !value.startsWith('/')) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority || uri.path.isEmpty) {
    return null;
  }
  return uri.toString();
}
