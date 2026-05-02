import 'package:flutter_riverpod/legacy.dart';

/// Holds the current route path and optional entity context so the AI
/// chat sheet can inject "I'm on Assets/AAPL detail page" into the
/// system prompt.
///
/// Updated by the router observer or by pages that want to expose
/// their current entity (e.g. asset detail sets the ticker).
class AiRouteContext {
  const AiRouteContext({
    required this.path,
    this.label,
    this.entityType,
    this.entityId,
  });

  /// Current route path, e.g. `/assets/AAPL`.
  final String path;

  /// Human-readable label, e.g. "Assets > AAPL".
  final String? label;

  /// Entity type, e.g. "asset", "account", "expense".
  final String? entityType;

  /// Entity identifier, e.g. the asset ID or ticker.
  final String? entityId;

  /// Builds a context string for the AI system prompt.
  String toSystemContext() {
    final buf = StringBuffer('User is currently on: $path');
    if (label != null) buf.write(' ($label)');
    if (entityType != null && entityId != null) {
      buf.write('. Viewing $entityType: $entityId');
    }
    return buf.toString();
  }
}

/// Global route context state. Updated from the shell / router observer.
final aiRouteContextProvider = StateProvider<AiRouteContext>(
  (_) => const AiRouteContext(path: '/'),
);
