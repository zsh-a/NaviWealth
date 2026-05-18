import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/rebalance/ui/target_allocation_editor_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

void main() {
  runAllVariants('target_allocation_editor_sheet', (tester, variant) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);

    await pumpAndSnapshotMobile(
      tester,
      name: 'target_allocation_editor_sheet',
      variant: variant,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 820),
            child: AppSheet(
              title: AppLocalizationsEn().targetAllocationEditorTitle,
              subtitle: AppLocalizationsEn().targetAllocationEditorSubtitle,
              child: TargetAllocationEditorSheet(dirty: dirty),
            ),
          ),
        ),
      ),
    );
  });
}
