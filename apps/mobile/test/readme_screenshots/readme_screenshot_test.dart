import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/forms/forms.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/fire/ui/fire_state_hero_card.dart';
import 'package:naviwealth/features/finance/ingest/data/providers.dart';
import 'package:naviwealth/features/finance/ingest/ui/ingest_review_page.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_hub_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/task_flow_golden_fixtures.dart';
import 'readme_screenshot_fixtures.dart';
import 'readme_screenshot_harness.dart';

const _output = '../../../../docs/assets/readme/generated';

void main() {
  late SharedPreferences preferences;

  setUpAll(() async {
    await AppFormatters.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'naviwealth.settings.base_currency': 'CNY',
      'naviwealth.forms.expense.account': 'golden-bank-cny',
      'naviwealth.forms.expense.category': 'golden-dining',
    });
    preferences = await SharedPreferences.getInstance();
  });

  readmeScreenshot(
    'README wealth overview',
    body: (tester) async {
      await pumpReadmeScreenshot(
        tester,
        profile: ReadmeScreenshotProfile.mobile,
        goldenPath: '$_output/wealth-overview.png',
        overrides: readmeWealthOverrides(),
        child: const WealthHubPage(),
      );
      expect(find.text('净资产'), findsWidgets);
      expect(find.text('¥137,899.80'), findsOneWidget);
    },
  );

  readmeScreenshot(
    'README FIRE insight',
    body: (tester) async {
      await pumpReadmeScreenshot(
        tester,
        profile: ReadmeScreenshotProfile.featureCard,
        goldenPath: '$_output/fire-insight.png',
        overrides: <Override>[readmeFireStateOverride()],
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FireStateHeroCard(view: readmeFireView()),
          ),
        ),
      );
      expect(find.text('自由状态'), findsOneWidget);
      expect(find.text('谨慎'), findsOneWidget);
    },
  );

  readmeScreenshot(
    'README smart ingest desktop',
    body: (tester) async {
      await pumpReadmeScreenshot(
        tester,
        profile: ReadmeScreenshotProfile.desktop,
        goldenPath: '$_output/smart-ingest.png',
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(preferences),
          formClockProvider.overrideWithValue(() => taskFlowLocalDate),
          pendingIngestReviewItemsProvider.overrideWith(
            (_) => Stream.value(taskFlowIngestItems),
          ),
          accountsStreamProvider.overrideWith(
            (_) => Stream<List<Account>>.value(
              taskFlowAccounts
                  .where((account) => account.category.name == 'asset')
                  .toList(growable: false),
            ),
          ),
        ],
        child: const IngestReviewPage(),
      );
      expect(find.text('录入待确认'), findsOneWidget);
      expect(find.text('Morning coffee'), findsWidgets);
    },
  );
}
