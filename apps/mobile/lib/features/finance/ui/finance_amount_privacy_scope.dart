import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../data/preferences/finance_amount_privacy_preference.dart';

/// Applies the FinanceOS amount-visibility preference to every Finance route.
class FinanceAmountPrivacyScope extends ConsumerWidget {
  const FinanceAmountPrivacyScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AmountPrivacyScope(
      hidden: ref.watch(financeAmountsHiddenProvider),
      child: child,
    );
  }
}
