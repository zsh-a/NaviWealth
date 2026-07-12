import '../auth/domain_scope.dart';
import 'sync_table_registry.dart';

String domainWireForPrefix(String prefix) => switch (prefix) {
  kFinanceDomainPrefix => DomainScope.finance.wire,
  kHealthDomainPrefix => DomainScope.health.wire,
  kKnowledgeDomainPrefix => DomainScope.knowledge.wire,
  kExecutionDomainPrefix => DomainScope.execution.wire,
  _ => throw ArgumentError.value(prefix, 'prefix', 'Unknown sync domain'),
};

String domainWireForLocalTable(String table) =>
    domainWireForPrefix(domainPrefixForTable(table));

String? domainWireForWireTable(String table) {
  for (final prefix in kSyncDomainPrefixes) {
    if (table.startsWith(prefix)) return domainWireForPrefix(prefix);
  }
  return null;
}

abstract class DomainGenerationStore {
  Future<Map<String, int>> readAll();
  Future<void> write(String domain, int generation);
}

class InMemoryDomainGenerationStore implements DomainGenerationStore {
  final Map<String, int> values = <String, int>{};

  @override
  Future<Map<String, int>> readAll() async => Map<String, int>.from(values);

  @override
  Future<void> write(String domain, int generation) async {
    values[domain] = generation;
  }
}

/// Clears local source/cache state after the server advances a domain reset
/// generation. Production uses the data-management registry; tests may use
/// [NoopDomainResetHandler] when reset behaviour is outside their scope.
abstract class DomainResetHandler {
  Future<void> resetLocalDomain(String domain);
}

class NoopDomainResetHandler implements DomainResetHandler {
  const NoopDomainResetHandler();

  @override
  Future<void> resetLocalDomain(String domain) async {}
}
