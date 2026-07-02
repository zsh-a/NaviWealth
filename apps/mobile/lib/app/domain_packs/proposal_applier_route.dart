import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/composition/composite_proposal_applier.dart';
import '../../core/ai/composition/proposal_applier.dart';

typedef DomainProposalApplierReader = Future<ProposalApplier> Function(Ref ref);

Future<ProposalApplierRoute> buildProposalApplierRoute(
  Ref ref, {
  required DomainProposalApplierReader readApplier,
  required Set<String> kinds,
  required Set<String> tablePrefixes,
}) async {
  return ProposalApplierRoute(
    applier: await readApplier(ref),
    kinds: kinds,
    tablePrefixes: tablePrefixes,
  );
}
