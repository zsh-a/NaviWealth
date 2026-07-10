import 'package:naviwealth/features/finance/domain/models/account.dart';

/// Versioned account mutation that can be conditionally reversed.
final class AccountMutationReceipt {
  const AccountMutationReceipt({required this.before, required this.after});

  final Account? before;
  final Account after;
}

final class AccountMutationConflict implements Exception {
  const AccountMutationConflict(this.message);

  final String message;

  @override
  String toString() => 'AccountMutationConflict: $message';
}
