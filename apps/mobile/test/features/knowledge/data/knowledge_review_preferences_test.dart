import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_review_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('review preferences persist per owner', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final ownerA = KnowledgeReviewPreferencesController(preferences, 'owner-a');

    await ownerA.setCadenceDays(14);
    await ownerA.setStaleAssumptionDays(45);

    final restoredA = KnowledgeReviewPreferencesController(
      preferences,
      'owner-a',
    );
    final ownerB = KnowledgeReviewPreferencesController(preferences, 'owner-b');
    expect(restoredA.state.cadenceDays, 14);
    expect(restoredA.state.staleAssumptionDays, 45);
    expect(ownerB.state.cadenceDays, 7);
    expect(ownerB.state.staleAssumptionDays, 90);
  });
}
