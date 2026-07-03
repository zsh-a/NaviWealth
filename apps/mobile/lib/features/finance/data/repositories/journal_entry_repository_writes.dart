part of 'journal_entry_repository.dart';

mixin JournalEntryRepositoryWriteMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;
  MutationStamper get _stamper;
  FxRateSource get _fx;
  String get _baseCurrency;
  Uuid get _uuid;

  /// Inserts a new JE plus its postings as one Drift transaction. The
  /// caller passes lightweight drafts ([JournalEntryDraft] / [PostingDraft])
  /// without sync metadata — the repo stamps them.
  ///
  /// Throws [JournalEntryUnbalancedException] before touching the DB if
  /// the postings don't balance.
  Future<JournalEntryWithPostings> create({
    required JournalEntryDraft entry,
    required List<PostingDraft> postings,
  }) async {
    if (postings.isEmpty) {
      throw const JournalEntryUnbalancedException(
        'Cannot create journal entry with zero postings.',
      );
    }
    final stamp = await _stamper.stamp();
    final jeId = entry.id ?? _uuid.v4();
    final domainEntry = JournalEntry(
      id: jeId,
      date: entry.date,
      settledOn: entry.settledOn,
      narration: entry.narration,
      payee: entry.payee,
      tagIds: List.unmodifiable(entry.tagIds),
      flag: entry.flag,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    final domainPostings = <Posting>[];
    for (var i = 0; i < postings.length; i++) {
      final draft = postings[i];
      domainPostings.add(
        Posting(
          id: draft.id ?? _uuid.v4(),
          journalEntryId: jeId,
          position: draft.position ?? i,
          accountId: draft.accountId,
          units: draft.units,
          unit: draft.unit,
          cost: draft.cost,
          price: draft.price,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    }

    final report = evaluateEntryBalance(
      entry: domainEntry,
      postings: domainPostings,
      fx: _fx,
      baseCurrency: _baseCurrency,
    );
    if (!report.isBalanced) {
      throw JournalEntryUnbalancedException.fromReport(report);
    }

    await _db.transaction(() async {
      await _db.into(_db.journalEntries).insert(_journalCompanion(domainEntry));
      await _outbox.enqueue(
        table: JournalEntryRepository._journalTable,
        rowId: jeId,
      );
      for (final p in domainPostings) {
        await _db.into(_db.postings).insert(_postingCompanion(p));
        await _outbox.enqueue(
          table: JournalEntryRepository._postingsTable,
          rowId: p.id,
        );
      }
    });
    return JournalEntryWithPostings(
      entry: domainEntry,
      postings: domainPostings,
    );
  }

  /// Atomically replace a JE's postings + (some of) its envelope
  /// fields. The semantics: in one Drift transaction,
  ///
  ///   1. update the JE row (date / settledOn / narration / payee /
  ///      flag / tagIds) with a fresh sync stamp,
  ///   2. soft-delete every still-live posting tied to this JE,
  ///   3. insert the replacement postings.
  ///
  /// Sync ops queued: a JE update + N posting deletes + M posting
  /// inserts, all under the same HLC tick. Peers replay the entire
  /// batch in one shot so the JE is never observed mid-replacement.
  ///
  /// Throws [JournalEntryUnbalancedException] before touching the DB
  /// if the new postings don't balance — same contract as [create].
  /// Throws [StateError] when [id] doesn't refer to an existing
  /// (non-tombstoned) JE.
  Future<JournalEntryWithPostings> replacePostings({
    required String id,
    required JournalEntryDraft entry,
    required List<PostingDraft> postings,
  }) async {
    if (postings.isEmpty) {
      throw const JournalEntryUnbalancedException(
        'Cannot replace journal entry with zero postings.',
      );
    }
    final existingRow =
        await (_db.select(_db.journalEntries)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
    if (existingRow == null) {
      throw StateError(
        'replacePostings called on missing or tombstoned JE id=$id',
      );
    }

    final stamp = await _stamper.stamp();
    final domainEntry = JournalEntry(
      id: id,
      date: entry.date,
      settledOn: entry.settledOn,
      narration: entry.narration,
      payee: entry.payee,
      tagIds: List.unmodifiable(entry.tagIds),
      flag: entry.flag,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    final domainPostings = <Posting>[];
    for (var i = 0; i < postings.length; i++) {
      final draft = postings[i];
      domainPostings.add(
        Posting(
          id: draft.id ?? _uuid.v4(),
          journalEntryId: id,
          position: draft.position ?? i,
          accountId: draft.accountId,
          units: draft.units,
          unit: draft.unit,
          cost: draft.cost,
          price: draft.price,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    }

    final report = evaluateEntryBalance(
      entry: domainEntry,
      postings: domainPostings,
      fx: _fx,
      baseCurrency: _baseCurrency,
    );
    if (!report.isBalanced) {
      throw JournalEntryUnbalancedException.fromReport(report);
    }

    await _db.transaction(() async {
      // 1. JE envelope update.
      final jeUpdate = JournalEntriesCompanion(
        date: Value(domainEntry.date),
        settledOn: Value(domainEntry.settledOn),
        narration: Value(domainEntry.narration),
        payee: Value(domainEntry.payee),
        flag: Value(domainEntry.flag),
        tagIdsJson: Value(jsonEncode(domainEntry.tagIds)),
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
      );
      await (_db.update(
        _db.journalEntries,
      )..where((t) => t.id.equals(id))).write(jeUpdate);
      await _outbox.enqueue(
        table: JournalEntryRepository._journalTable,
        rowId: id,
      );

      // 2. Tombstone the existing postings + queue delete ops.
      final oldPostingRows =
          await (_db.select(_db.postings)
                ..where((t) => t.journalEntryId.equals(id))
                ..where((t) => t.deletedAt.isNull()))
              .get();
      final tombstone = PostingsCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );
      await (_db.update(_db.postings)
            ..where((t) => t.journalEntryId.equals(id))
            ..where((t) => t.deletedAt.isNull()))
          .write(tombstone);
      for (final p in oldPostingRows) {
        await _outbox.enqueue(
          table: JournalEntryRepository._postingsTable,
          rowId: p.id,
        );
      }

      // 3. Insert the replacements.
      for (final p in domainPostings) {
        await _db.into(_db.postings).insert(_postingCompanion(p));
        await _outbox.enqueue(
          table: JournalEntryRepository._postingsTable,
          rowId: p.id,
        );
      }
    });

    return JournalEntryWithPostings(
      entry: domainEntry,
      postings: domainPostings,
    );
  }

  /// Soft-delete the JE plus all its postings. Tombstones cascade in
  /// the same transaction so a partially-tombstoned ledger never
  /// surfaces from a crash mid-delete.
  Future<void> softDelete(String id) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final jeUpdate = JournalEntriesCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );
      await (_db.update(
        _db.journalEntries,
      )..where((t) => t.id.equals(id))).write(jeUpdate);
      await _outbox.enqueue(
        table: JournalEntryRepository._journalTable,
        rowId: id,
      );

      final postingRows =
          await (_db.select(_db.postings)
                ..where((t) => t.journalEntryId.equals(id))
                ..where((t) => t.deletedAt.isNull()))
              .get();
      final postingUpdate = PostingsCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );
      await (_db.update(_db.postings)
            ..where((t) => t.journalEntryId.equals(id))
            ..where((t) => t.deletedAt.isNull()))
          .write(postingUpdate);
      for (final p in postingRows) {
        await _outbox.enqueue(
          table: JournalEntryRepository._postingsTable,
          rowId: p.id,
        );
      }
    });
  }
}
