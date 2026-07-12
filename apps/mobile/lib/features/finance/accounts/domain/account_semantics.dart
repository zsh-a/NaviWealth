import 'package:naviwealth/features/finance/domain/models/enums.dart';

/// Account kinds that represent user-owned custody/payment containers.
///
/// Debt belongs to the liabilities feature and tangible or manually valued
/// objects belong to assets. Keeping those concepts out of the account UI
/// gives each object one creation flow and one detail surface.
const List<AccountCategory> kCustodyAccountCategories = [
  AccountCategory.cash,
  AccountCategory.bank,
  AccountCategory.broker,
  AccountCategory.crypto,
];

bool isCustodyAccountCategory(AccountCategory category) =>
    kCustodyAccountCategories.contains(category);
