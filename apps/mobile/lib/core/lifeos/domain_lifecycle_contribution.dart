part of 'domain_pack.dart';

/// Lifecycle contributions owned by one domain.
final class DomainLifecycleContribution {
  const DomainLifecycleContribution({
    this.memoryBootstrapBuilder,
    this.backgroundBootstrapBuilder,
    this.providerOverridesBuilder,
  });

  /// Eager Memory Runtime indexer bootstrap. Null when the domain has no
  /// memory indexers with source streams.
  final DomainBootstrapBuilder? memoryBootstrapBuilder;

  /// Eager background-job bootstrap. Null when the domain has no startup
  /// background scheduler or pending wakeup drain.
  final DomainBootstrapBuilder? backgroundBootstrapBuilder;

  /// Build-level provider overrides for domain-owned seams that do not
  /// belong in `bootstrap.dart`. These are registered for every pack in
  /// the build inventory; opt-in-gated work should still check opt-ins
  /// inside the contributing provider.
  final DomainProviderOverridesBuilder? providerOverridesBuilder;
}
