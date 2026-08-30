import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../l10n/gen/app_localizations.dart';

/// Resolves [LiabilityType] / [RepaymentMethod] / [LiabilityRateType] enum
/// values to their localized strings. Centralized so the list, detail, and
/// form screens render the same labels without each one carrying its own
/// switch.
String liabilityTypeLabel(AppLocalizations l10n, LiabilityType type) {
  switch (type) {
    case LiabilityType.mortgage:
      return l10n.liabilityTypeMortgage;
    case LiabilityType.carLoan:
      return l10n.liabilityTypeCarLoan;
    case LiabilityType.creditCard:
      return l10n.liabilityTypeCreditCard;
    case LiabilityType.consumerLoan:
      return l10n.liabilityTypeConsumerLoan;
    case LiabilityType.studentLoan:
      return l10n.liabilityTypeStudentLoan;
    case LiabilityType.marginLoan:
      return l10n.liabilityTypeMarginLoan;
    case LiabilityType.other:
      return l10n.liabilityTypeOther;
  }
}

String repaymentMethodLabel(AppLocalizations l10n, RepaymentMethod method) {
  switch (method) {
    case RepaymentMethod.equalInstallment:
      return l10n.liabilityMethodEqualInstallment;
    case RepaymentMethod.equalPrincipal:
      return l10n.liabilityMethodEqualPrincipal;
  }
}

String rateTypeLabel(AppLocalizations l10n, LiabilityRateType rate) {
  switch (rate) {
    case LiabilityRateType.fixed:
      return l10n.liabilityRateTypeFixed;
    case LiabilityRateType.lprFloating:
      return l10n.liabilityRateTypeLpr;
  }
}
