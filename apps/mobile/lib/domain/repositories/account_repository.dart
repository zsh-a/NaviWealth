import '../entities/account.dart';

/// Domain-side contract for account persistence. Concrete implementations
/// live under `lib/data/repositories/` and target a specific storage
/// backend (Drift, in-memory, remote, etc.).
abstract class AccountRepository {
  Future<List<Account>> listAll({bool includeArchived = false});
  Stream<List<Account>> watchAll({bool includeArchived = false});
  Future<Account?> findById(String id);
  Future<void> upsert(Account account);
  Future<void> archive(String id);
  Future<void> softDelete(String id);
}
