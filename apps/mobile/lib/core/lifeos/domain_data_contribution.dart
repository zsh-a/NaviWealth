part of 'domain_pack.dart';

/// Data contributions owned by one domain.
final class DomainDataContribution {
  const DomainDataContribution({
    this.lifeSignalBuilder,
    this.sourceRouteResolver,
    this.localTableCountsBuilder,
    this.dataManagementSpec,
    this.shareIntentHandlers = const <DomainShareIntentHandler>[],
  });

  /// Domain-owned signals and evaluated source-family evidence for Life.
  final DomainLifeSignalBuilder? lifeSignalBuilder;

  /// Domain-owned route resolution for Execution source references.
  final DomainSourceRouteResolver? sourceRouteResolver;

  /// Debug diagnostics for Settings → Sync. Domains own their table SQL;
  /// the Settings page reads the domain-neutral aggregate provider.
  final DomainLocalTableCountsBuilder? localTableCountsBuilder;

  /// Domain-owned source/cache inventory for Settings → Data & Storage.
  /// Registered for all packs, including disabled optional domains, so users
  /// can inspect and clear residual local data without re-enabling a domain.
  final DomainDataManagementSpec? dataManagementSpec;

  /// Domain-owned handlers for OS share-sheet payloads.
  ///
  /// App code receives plugin events and converts them to [SharedIntentPayload].
  /// Domains decide whether and how to persist payloads they understand.
  final List<DomainShareIntentHandler> shareIntentHandlers;
}
