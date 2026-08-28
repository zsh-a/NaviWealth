import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/forms/forms.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container(SharedPreferences prefs) => ProviderContainer(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts empty when nothing has been persisted', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    final defaults = container.read(formDefaultsProvider);
    expect(defaults.tradeAccountId, isNull);
    expect(defaults.expenseAccountId, isNull);
    expect(defaults.incomeAccountId, isNull);
    expect(defaults.incomeCurrency, isNull);
    expect(defaults.assetAccountId, isNull);
    expect(defaults.expenseCategoryId, isNull);
  });

  test('hydrates from previously persisted values on first read', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'naviwealth.forms.trade.account': 'acct-trade',
      'naviwealth.forms.trade.currency': 'USD',
      'naviwealth.forms.expense.account': 'acct-bank',
      'naviwealth.forms.expense.category': 'cat-food',
      'naviwealth.forms.expense.currency': 'CNY',
      'naviwealth.forms.income.account': 'acct-income',
      'naviwealth.forms.income.currency': 'USD',
      'naviwealth.forms.asset.account': 'acct-broker',
      'naviwealth.forms.asset.currency': 'HKD',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    final defaults = container.read(formDefaultsProvider);
    expect(defaults.tradeAccountId, 'acct-trade');
    expect(defaults.tradeCurrency, 'USD');
    expect(defaults.expenseAccountId, 'acct-bank');
    expect(defaults.expenseCategoryId, 'cat-food');
    expect(defaults.expenseCurrency, 'CNY');
    expect(defaults.incomeAccountId, 'acct-income');
    expect(defaults.incomeCurrency, 'USD');
    expect(defaults.assetAccountId, 'acct-broker');
    expect(defaults.assetCurrency, 'HKD');
  });

  test('rememberExpense persists each field independently', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    await container
        .read(formDefaultsProvider.notifier)
        .rememberExpense(
          accountId: 'acct-1',
          categoryId: 'cat-1',
          currency: 'CNY',
        );

    expect(prefs.getString('naviwealth.forms.expense.account'), 'acct-1');
    expect(prefs.getString('naviwealth.forms.expense.category'), 'cat-1');
    expect(prefs.getString('naviwealth.forms.expense.currency'), 'CNY');

    // A subsequent partial write must not blank out fields that the
    // caller didn't touch — most save flows pass `null` when the user
    // didn't change a particular field.
    await container
        .read(formDefaultsProvider.notifier)
        .rememberExpense(accountId: 'acct-2');
    expect(prefs.getString('naviwealth.forms.expense.account'), 'acct-2');
    expect(prefs.getString('naviwealth.forms.expense.category'), 'cat-1');
    expect(prefs.getString('naviwealth.forms.expense.currency'), 'CNY');

    final state = container.read(formDefaultsProvider);
    expect(state.expenseAccountId, 'acct-2');
    expect(state.expenseCategoryId, 'cat-1');
    expect(state.expenseCurrency, 'CNY');
  });

  test('rememberTrade and rememberAsset are namespaced separately', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    await container
        .read(formDefaultsProvider.notifier)
        .rememberTrade(accountId: 'broker-1', currency: 'USD');
    await container
        .read(formDefaultsProvider.notifier)
        .rememberAsset(accountId: 'bank-1', currency: 'CNY');

    final state = container.read(formDefaultsProvider);
    expect(state.tradeAccountId, 'broker-1');
    expect(state.tradeCurrency, 'USD');
    expect(state.assetAccountId, 'bank-1');
    expect(state.assetCurrency, 'CNY');
    // Trade fields stayed put after the asset write.
    expect(state.expenseAccountId, isNull);
  });

  test('rememberIncome persists account and currency independently', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    await container
        .read(formDefaultsProvider.notifier)
        .rememberIncome(accountId: 'bank-1', currency: 'CNY');
    await container
        .read(formDefaultsProvider.notifier)
        .rememberIncome(accountId: 'bank-2');

    final state = container.read(formDefaultsProvider);
    expect(state.incomeAccountId, 'bank-2');
    expect(state.incomeCurrency, 'CNY');
    expect(prefs.getString('naviwealth.forms.income.account'), 'bank-2');
    expect(prefs.getString('naviwealth.forms.income.currency'), 'CNY');
  });

  test('empty strings are skipped (treated as no-op)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'naviwealth.forms.expense.account': 'acct-original',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    await container
        .read(formDefaultsProvider.notifier)
        .rememberExpense(accountId: '', categoryId: '');

    expect(
      prefs.getString('naviwealth.forms.expense.account'),
      'acct-original',
    );
  });
}
