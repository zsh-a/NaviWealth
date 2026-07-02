import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lifeos/domain_pack.dart';
import 'providers.dart';

typedef LocalTableCounts = Map<String, int>;

/// Aggregates debug local row counts contributed by active domains.
final localTableCountsProvider = FutureProvider<LocalTableCounts>((ref) async {
  ref.watch(syncStatusEventStreamProvider);
  final packs = ref.watch(activeDomainPacksProvider);
  final countMaps = await Future.wait<LocalTableCounts>([
    for (final pack in packs)
      if (pack.localTableCountsBuilder case final builder?) builder(ref),
  ]);
  return {for (final counts in countMaps) ...counts};
});
