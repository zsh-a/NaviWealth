import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

/// A source row, confirmed personal data, and linked local history.
Future<void> seedOwnerData(AppDatabase db, String owner, String prefix) async {
  await db.customStatement(
    'INSERT INTO recurring_transactions '
    '(id, owner_user_id, template_journal_build_json, rrule, next_due_at, '
    'updated_at, updated_by_device, hlc) VALUES (?, ?, ?, ?, 1, 1, ?, ?)',
    [
      '$prefix-recurring',
      owner,
      '{}',
      'FREQ=MONTHLY',
      'device',
      '1.0000-device',
    ],
  );
  await seedProfileFact(db, owner, '$prefix-profile');
  await db.customStatement(
    'INSERT INTO events (id, owner_user_id, kind, occurred_at, observed_at, '
    'source_family, source_row_id, source_fingerprint, summary, facts_json, '
    'entities_json) VALUES (?, ?, ?, 1, 1, ?, ?, ?, ?, ?, ?)',
    [
      '$prefix-event',
      owner,
      'confirmed',
      'recurring_transactions',
      '$prefix-recurring',
      'fingerprint',
      'summary',
      '{}',
      '[]',
    ],
  );
  await db.customStatement(
    'INSERT INTO memories (id, owner_user_id, kind, role, authority, '
    'provenance_json, source, source_id, source_event_id, title, summary, '
    'payload_json, entities_json, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
    [
      '$prefix-memory',
      owner,
      'semantic',
      'guidance',
      'user_confirmed',
      '{}',
      'personal_profile_facts',
      '$prefix-profile',
      '$prefix-event',
      'title',
      'confirmed preference',
      '{}',
      '[]',
    ],
  );
  await db.customStatement(
    "INSERT INTO memory_embeddings VALUES (?, 'test', 1, X'0000803f')",
    ['$prefix-memory'],
  );
  await db.customStatement(
    'INSERT INTO chat_sessions (id, owner_user_id, title, created_at, updated_at) '
    'VALUES (?, ?, ?, 1, 1)',
    ['$prefix-chat', owner, 'history'],
  );
  await db.customStatement(
    'INSERT INTO chat_messages (id, session_id, owner_user_id, role, content, '
    'status, created_at) VALUES (?, ?, ?, ?, ?, ?, 1)',
    ['$prefix-message', '$prefix-chat', owner, 'user', 'keep me', 'completed'],
  );
  await db.customStatement(
    'INSERT INTO conversation_checkpoints VALUES (?, ?, ?, 1, ?, 1, 1, ?, 1, 1)',
    ['$prefix-chat', owner, '$prefix-message', 'fingerprint', '{}'],
  );
}

Future<void> seedProfileFact(AppDatabase db, String owner, String id) =>
    db.customStatement(
      'INSERT INTO personal_profile_facts '
      '(id, owner_user_id, kind, fact_key, value_json, summary, authority, '
      'provenance_json, confidence, confirmed_at, valid_from, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1, 1, 1, 1)',
      [
        id,
        owner,
        'preference',
        'language',
        '"zh"',
        'confirmed language',
        'user_confirmed',
        '{}',
      ],
    );

Future<String> ownerOf(AppDatabase db, String table, String id) async =>
    (await db
            .customSelect(
              'SELECT owner_user_id FROM $table WHERE id = ?',
              variables: [Variable(id)],
            )
            .getSingle())
        .read<String>('owner_user_id');
