import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/activation/data/finance_activation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('confirmed import milestone survives controller recreation', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = FinanceImportConfirmedController(
      preferences,
      ownerUserId: 'owner-a',
    );

    expect(controller.state, isFalse);
    await controller.markConfirmed();

    final restored = FinanceImportConfirmedController(
      preferences,
      ownerUserId: 'owner-a',
    );
    final otherOwner = FinanceImportConfirmedController(
      preferences,
      ownerUserId: 'owner-b',
    );
    expect(restored.state, isTrue);
    expect(otherOwner.state, isFalse);
  });

  test('setup guide dismissal persists per owner', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = FinanceActivationDismissedController(
      preferences,
      ownerUserId: 'owner-a',
    );

    await controller.dismiss();

    expect(
      FinanceActivationDismissedController(
        preferences,
        ownerUserId: 'owner-a',
      ).state,
      isTrue,
    );
    expect(
      FinanceActivationDismissedController(
        preferences,
        ownerUserId: 'owner-b',
      ).state,
      isFalse,
    );
  });
}
