/// Explicit ownership for AI policy, artifacts and diagnostics.
/// Business identities use the same DomainScope as the LifeOS registry.
library;

import '../../auth/domain_scope.dart';

export '../../auth/domain_scope.dart' show DomainScope;

sealed class AiDomain {
  const AiDomain();
  const factory AiDomain.domain(DomainScope scope) = BusinessAiDomain;
  const factory AiDomain.shell() = ShellAiDomain;
  const factory AiDomain.global() = GlobalAiDomain;

  DomainScope? get scope;
  String get wire;

  static AiDomain fromScope(DomainScope? scope) =>
      scope == null ? const AiDomain.global() : AiDomain.domain(scope);

  static AiDomain fromWire(Object? value) {
    if (value == 'shell') return const AiDomain.shell();
    if (value == 'global') return const AiDomain.global();
    final scope = value is String ? DomainScope.tryParse(value) : null;
    if (scope != null) return AiDomain.domain(scope);
    throw FormatException('Unknown or missing AI domain: $value');
  }

  @override
  bool operator ==(Object other) => other is AiDomain && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

final class BusinessAiDomain extends AiDomain {
  const BusinessAiDomain(this.scope);
  @override
  final DomainScope scope;
  @override
  String get wire => scope.wire;
}

final class ShellAiDomain extends AiDomain {
  const ShellAiDomain();
  @override
  DomainScope? get scope => null;
  @override
  String get wire => 'shell';
}

final class GlobalAiDomain extends AiDomain {
  const GlobalAiDomain();
  @override
  DomainScope? get scope => null;
  @override
  String get wire => 'global';
}
