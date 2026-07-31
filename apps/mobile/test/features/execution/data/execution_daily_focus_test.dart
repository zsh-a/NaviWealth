import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/execution/data/execution_daily_focus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('daily focus persists at most three unique actions', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = ExecutionDailyFocusController(preferences, 'user-1');

    await controller.set(const <String>['a', 'b', 'a', 'c', 'd']);

    expect(controller.state, const <String>['a', 'b', 'c']);
    final restored = ExecutionDailyFocusController(preferences, 'user-1');
    expect(restored.state, const <String>['a', 'b', 'c']);
  });

  test('toggle refuses to evict a Top 3 action when full', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = ExecutionDailyFocusController(preferences, 'user-1');

    await controller.set(const <String>['a', 'b', 'c']);
    final changed = await controller.toggle('d');

    expect(changed, isFalse);
    expect(controller.state, const <String>['a', 'b', 'c']);
    await controller.replace('a', 'd');
    expect(controller.state, const <String>['d', 'b', 'c']);
    await controller.toggle('c');
    expect(controller.state, const <String>['d', 'b']);
  });

  test('focus from a previous day is not restored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      executionDailyFocusKey('user-1'): jsonEncode(<String, Object?>{
        'day': '2000-01-01',
        'action_ids': <String>['stale'],
      }),
    });
    final preferences = await SharedPreferences.getInstance();

    expect(ExecutionDailyFocusController(preferences, 'user-1').state, isEmpty);
  });

  test('focus is isolated by owner', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    await ExecutionDailyFocusController(
      preferences,
      'user-1',
    ).set(const <String>['a']);

    expect(ExecutionDailyFocusController(preferences, 'user-2').state, isEmpty);
  });
}
