/// Production LifeOS domain inventory (`docs/architecture/lifeos-shell.md` §4).
///
/// App-level composition stays here: each domain has a focused pack file under
/// `app/domain_packs/`, while this file remains the single production list that
/// `bootstrap.dart` registers through [domainPackRegistryProvider].
library;

import '../core/lifeos/domain_pack.dart';
import 'domain_packs/execution_pack.dart';
import 'domain_packs/finance_pack.dart';
import 'domain_packs/health_pack.dart';
import 'domain_packs/knowledge_pack.dart';

export 'domain_packs/execution_pack.dart' show kExecutionPack;
export 'domain_packs/finance_pack.dart' show kFinancePack;
export 'domain_packs/health_pack.dart' show kHealthPack;
export 'domain_packs/knowledge_pack.dart' show kKnowledgePack;

/// Production inventory. Tests can override [domainPackRegistryProvider] with
/// a subset for reduced-matrix scenarios.
final List<DomainPack> kAllDomainPacks = <DomainPack>[
  kFinancePack,
  kHealthPack,
  kKnowledgePack,
  kExecutionPack,
];
