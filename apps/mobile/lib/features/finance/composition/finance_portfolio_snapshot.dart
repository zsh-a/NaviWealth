/// FinanceOS implementation of the portfolio snapshot seam
/// (`docs/architecture/lifeos-shell.md` §4, D-1.6b).
///
/// Wraps `devicePortfolioSnapshotProvider` (the existing investment-
/// domain snapshot builder) as a `PortfolioSnapshotReader` closure.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/portfolio_snapshot.dart';
import '../../investment/data/providers.dart';

final financePortfolioSnapshotReaderProvider =
    Provider<PortfolioSnapshotReader>((ref) {
      return () => ref.read(devicePortfolioSnapshotProvider.future);
    });
