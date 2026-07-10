import 'package:naviwealth/features/finance/domain/models/price_observation.dart';

/// Versioned price mutation that can be conditionally reversed.
final class PriceMutationReceipt {
  const PriceMutationReceipt({required this.before, required this.after});

  final PriceObservation? before;
  final PriceObservation after;
}

final class PriceMutationConflict implements Exception {
  const PriceMutationConflict(this.message);

  final String message;

  @override
  String toString() => 'PriceMutationConflict: $message';
}
