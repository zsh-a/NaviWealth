import 'package:flutter/widgets.dart';

/// Page-local switch for hiding exact monetary values.
class AmountPrivacyScope extends InheritedWidget {
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
  static const hiddenSemanticsLabel = 'Amount hidden';

  @override
  bool updateShouldNotify(AmountPrivacyScope oldWidget) {
    return hidden != oldWidget.hidden;
  }
}
