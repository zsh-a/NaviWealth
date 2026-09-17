import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/scheduled_agent_store.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/scheduled_task_editor.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/test_database.dart';

void main() {
  testWidgets('creates a weekly read-only task through the guarded editor', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = makeTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'alice'),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showScheduledTaskEditor(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).at(0), 'My weekly report');
    await tester.enterText(
      find.byType(EditableText).at(1),
      'Review my wealth and cite evidence',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final tasks = await ScheduledAgentStore(db, 'alice').list();
    expect(tasks.single.title, 'My weekly report');
    expect(tasks.single.schedule.weekdayLocal, 7);
    expect(tasks.single.schedule.preferredHourLocal, 20);
    expect(tester.takeException(), isNull);
  });
}
