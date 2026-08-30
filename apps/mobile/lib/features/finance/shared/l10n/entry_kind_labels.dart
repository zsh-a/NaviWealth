import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';

import '../../../../l10n/gen/app_localizations.dart';

String entryKindLabel(AppLocalizations l10n, EntryKind kind) {
  return switch (kind) {
    EntryKind.trade => l10n.entryKindTrade,
    EntryKind.transfer => l10n.entryKindTransfer,
    EntryKind.income => l10n.entryKindIncome,
    EntryKind.expense => l10n.entryKindExpense,
    EntryKind.payment => l10n.entryKindPayment,
    EntryKind.adjustment => l10n.entryKindAdjustment,
    EntryKind.opening => l10n.entryKindOpening,
    EntryKind.other => l10n.entryKindOther,
  };
}
