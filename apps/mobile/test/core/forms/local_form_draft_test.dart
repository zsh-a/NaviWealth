import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/forms/local_form_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  late LocalFormDraftStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    store = LocalFormDraftStore(preferences, owner: 'owner');
  });

  test(
    'snapshots are isolated by owner and form, including dotted ids',
    () async {
      await store.write('finance.expense.new', {'amount': '12.50'});
      expect(store.read('finance.expense.new'), {'amount': '12.50'});
      expect(store.read('execution.action.new'), isNull);
      expect(
        LocalFormDraftStore(
          preferences,
          owner: 'other',
        ).read('finance.expense.new'),
        isNull,
      );
      final dotted = LocalFormDraftStore(preferences, owner: 'owner.finance');
      await dotted.write('expense.new', {'amount': '25'});
      expect(store.read('finance.expense.new'), {'amount': '12.50'});
    },
  );

  test('invalid, expired and oversized drafts are ignored', () async {
    await store.write('finance.expense.new', {'amount': '1'});
    final key = preferences.getKeys().single;
    await preferences.setString(key, '{broken');
    expect(store.read('finance.expense.new'), isNull);
    await preferences.setString(
      key,
      jsonEncode({
        'version': 1,
        'savedAt': DateTime.now()
            .subtract(const Duration(days: 8))
            .toIso8601String(),
        'payload': {'amount': '2'},
      }),
    );
    expect(store.read('finance.expense.new'), isNull);
    await store.clear('finance.expense.new');
    await store.write('finance.expense.new', {'note': 'x' * 70000});
    expect(store.read('finance.expense.new'), isNull);
  });

  test('pending restore blocks fresh typing until the user decides', () async {
    await store.write('finance.expense.new', {'amount': '10'});
    final session = LocalFormDraftSession(store, 'finance.expense.new');
    session.capture({'amount': '20'});
    session.flush();
    await store.clear('barrier');
    expect(store.read('finance.expense.new'), {'amount': '10'});
    session.accept();
    session.capture({'amount': '30'});
    session.dispose();
    await store.clear('barrier');
    expect(store.read('finance.expense.new'), {'amount': '30'});
  });

  test(
    'save or explicit discard cancels pending autosave and clears input',
    () async {
      final session = LocalFormDraftSession(store, 'execution.action.new');
      session.capture({'title': 'First'});
      session.flush();
      session.capture({'title': 'Last'});
      session.complete();
      session.dispose();
      await store.clear('barrier');
      expect(store.read('execution.action.new'), isNull);
    },
  );

  test(
    'domain reset removes only the current owner and chosen domain',
    () async {
      final other = LocalFormDraftStore(preferences, owner: 'other');
      await store.write('finance.expense.new', {'amount': '1'});
      await store.write('finance.ingest.review-view', {'query': 'coffee'});
      await store.write('execution.action.new:plan', {'title': 'Plan'});
      await other.write('finance.expense.new', {'amount': '2'});
      await store.clearDomain('finance');
      expect(store.read('finance.expense.new'), isNull);
      expect(store.read('finance.ingest.review-view'), isNull);
      expect(store.read('execution.action.new:plan'), {'title': 'Plan'});
      expect(other.read('finance.expense.new'), {'amount': '2'});
    },
  );

  test(
    'pending input from an open page cannot revive after a domain reset',
    () async {
      final session = LocalFormDraftSession(store, 'finance.expense.new');
      session.capture({'amount': '10'});
      await LocalFormDraftStore(
        preferences,
        owner: 'owner',
      ).clearDomain('finance');
      session.dispose();
      await store.clear('barrier');
      expect(store.read('finance.expense.new'), isNull);
    },
  );
}
