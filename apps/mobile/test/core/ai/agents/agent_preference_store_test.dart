import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  test(
    'SqliteAgentPreferenceStore defaults missing preferences to enabled',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentPreferenceStore(db: db);

      final pref = await store.preferenceFor(
        ownerUserId: 'user-1',
        agentId: 'agent-1',
      );

      expect(pref.enabled, isTrue);
      expect(
        await store.isEnabled(ownerUserId: 'user-1', agentId: 'agent-1'),
        isTrue,
      );
    },
  );

  test(
    'SqliteAgentPreferenceStore persists enabled toggles per owner',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentPreferenceStore(db: db);
      final updatedAt = DateTime.utc(2026, 7, 5, 8);

      await store.setEnabled(
        ownerUserId: 'user-1',
        agentId: 'agent-1',
        enabled: false,
        updatedAt: updatedAt,
      );

      expect(
        await store.isEnabled(ownerUserId: 'user-1', agentId: 'agent-1'),
        isFalse,
      );
      expect(
        await store.isEnabled(ownerUserId: 'user-2', agentId: 'agent-1'),
        isTrue,
      );

      final saved = await store.preferenceFor(
        ownerUserId: 'user-1',
        agentId: 'agent-1',
      );
      expect(saved.updatedAt, updatedAt);

      await store.setEnabled(
        ownerUserId: 'user-1',
        agentId: 'agent-1',
        enabled: true,
        updatedAt: updatedAt.add(const Duration(minutes: 1)),
      );

      expect(
        await store.isEnabled(ownerUserId: 'user-1', agentId: 'agent-1'),
        isTrue,
      );
      final rows = await store.listForOwner(ownerUserId: 'user-1');
      expect(rows.map((pref) => pref.agentId), ['agent-1']);
    },
  );
}
