import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/execution/data/execution_daily_focus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('daily focus persists at most three unique actions', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = ExecutionDailyFocusController(preferences);

    await controller.set(const <String>['a', 'b', 'a', 'c', 'd']);

    expect(controller.state, const <String>['a', 'b', 'c']);
    final restored = ExecutionDailyFocusController(preferences);
    expect(restored.state, const <String>['a', 'b', 'c']);
  });

  test('toggle rotates the oldest focus after reaching Top 3', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = ExecutionDailyFocusController(preferences);

    await controller.set(const <String>['a', 'b', 'c']);
    await controller.toggle('d');

    expect(controller.state, const <String>['b', 'c', 'd']);
    await controller.toggle('c');
    expect(controller.state, const <String>['b', 'd']);
  });

  test('focus from a previous day is not restored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kExecutionDailyFocusKey: jsonEncode(<String, Object?>{
        'day': '2000-01-01',
        'action_ids': <String>['stale'],
      }),
    });
    final preferences = await SharedPreferences.getInstance();

    expect(ExecutionDailyFocusController(preferences).state, isEmpty);
  });
}
