import 'package:flutter_riverpod/legacy.dart';

import '../../../core/auth/domain_scope.dart';

/// Ambient AI context — the single fact source for "where is the user
/// right now" used by every AI surface.
///
/// Holds the current route path, its owning [DomainScope] (derived from
/// the path via `domainForRoute`), and an optional currently-viewed
/// entity. The system-prompt composer reads this to inject "I'm on
/// Assets/AAPL detail page"; the `askAi()` helper reads `domain` so no
/// call site needs to hard-code which OS it lives in.
///
/// Updated by the outer shell on every route change.
class AiContext {
  const AiContext({
    required this.path,
    this.domain,
    this.label,
    this.entityType,
    this.entityId,
  });

  /// Current route path, e.g. `/wealth/assets/AAPL`.
  final String path;

  /// Owning LifeOS domain. `null` for shell-level routes (login,
  /// onboarding, `/settings/*`); call sites that need a concrete domain
  /// fall back to [DomainScope.finance] (the always-on seed domain).
  final DomainScope? domain;

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

/// Global ambient-context state. Updated from the outer shell whenever
/// the route changes.
final aiContextProvider = StateProvider<AiContext>(
  (_) => const AiContext(path: '/', domain: DomainScope.finance),
);
