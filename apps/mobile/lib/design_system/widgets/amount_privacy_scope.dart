import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';

/// Page-local switch for hiding exact monetary values.
class AmountPrivacyScope extends InheritedTheme {
  const AmountPrivacyScope({
    super.key,
    required this.hidden,
    required super.child,
  });

  final bool hidden;

  static bool isHiddenOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AmountPrivacyScope>()
            ?.hidden ??
        false;
  }

  static const mask = '••••';

  /// Localized semantics label for hidden amounts.
  static String hiddenSemanticsLabelOf(BuildContext context) =>
      AppLocalizations.of(context).amountHidden;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      AmountPrivacyScope(hidden: hidden, child: child);

  @override
  bool updateShouldNotify(AmountPrivacyScope oldWidget) {
    return hidden != oldWidget.hidden;
  }
}
