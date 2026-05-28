/// KnowledgeOS shell-seam overrides (`docs/lifeos-shell.md` §4,
/// `docs/knowledgeos-domain.md` §15.6).
///
/// This bundle is the **single owner** of the two cross-domain propose
/// seams. Riverpod 3 throws on a double-override, so `finance_bootstrap.dart`
/// deliberately does NOT override them — it only exposes
/// `financeProposalApplierProvider` + `kFinanceProposalKinds` as plain
/// providers for the composite here to read:
///
///  - `proposalApplierProvider` → a [CompositeProposalApplier] that routes
///    `knowledge_*` kinds to [KnowledgeProposalApplier] and everything else
///    to the Finance applier (the prior single-domain behaviour).
///  - `proposalKindRegistryProvider` → Finance kinds ∪ KnowledgeOS kinds,
///    so the propose card can render the new `knowledge_merge` /
///    `knowledge_routine` cards.
///
/// The applier resolves lazily; in a Knowledge-opt-out build the knowledge
/// `propose_*` tools are never registered, so the knowledge routes simply
/// never fire and the composite behaves exactly like the Finance applier.
library;

import 'package:flutter_riverpod/misc.dart';

import '../../../core/ai/composition/composite_proposal_applier.dart';
import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_kind_registry.dart';
import '../../finance/composition/finance_proposal_applier.dart';
import '../../finance/composition/finance_proposal_kinds.dart';
import 'knowledge_proposal_applier.dart';
import 'knowledge_proposal_kinds.dart';

/// Every KnowledgeOS shell-seam override in one place. Spread by
/// `bootstrap.dart` after the Finance bundle.
List<Override> knowledgeCompositionOverrides() => [
  // Compose the chat propose-card applier: KnowledgeOS owns `knowledge_*`
  // kinds, Finance handles the rest.
  proposalApplierProvider.overrideWith((ref) async {
    final knowledge = await ref.watch(knowledgeProposalApplierProvider.future);
    final finance = await ref.watch(financeProposalApplierProvider.future);
    return CompositeProposalApplier(
      routes: [
        ProposalApplierRoute(
          applier: knowledge,
          kinds: kKnowledgeProposalAppliedKinds,
          tablePrefix: kKnowledgeTablePrefix,
        ),
      ],
      fallback: finance,
    );
  }),
  // Union the propose-card kind registries so KnowledgeOS cards render.
  proposalKindRegistryProvider.overrideWith(
    (ref) => [...kFinanceProposalKinds, ...kKnowledgeProposalKinds],
  ),
];
