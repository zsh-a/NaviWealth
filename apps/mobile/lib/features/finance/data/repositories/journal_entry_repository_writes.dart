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
  }) async => (await createWithReceipt(entry: entry, postings: postings)).after;

  Future<JournalMutationReceipt> createWithReceipt({
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

    late final JournalEntryWithPostings after;
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
      // Snapshot the canonical persisted representation. Drift converters
      // normalize values such as Decimal prices, so comparing Undo against
      // the pre-insert draft would report a false conflict.
      after = (await _liveEntry(jeId))!;
    });
    return JournalMutationReceipt(before: null, after: after);
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
  }) async => (await replacePostingsWithReceipt(
    id: id,
    entry: entry,
    postings: postings,
  )).after;

  Future<JournalMutationReceipt> replacePostingsWithReceipt({
    required String id,
    required JournalEntryDraft entry,
    required List<PostingDraft> postings,
  }) async {
    if (postings.isEmpty) {
      throw const JournalEntryUnbalancedException(
        'Cannot replace journal entry with zero postings.',
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

    late final JournalEntryWithPostings before;
    late final JournalEntryWithPostings after;
    await _db.transaction(() async {
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
      final oldPostingRows =
          await (_db.select(_db.postings)
                ..where((t) => t.journalEntryId.equals(id))
                ..where((t) => t.deletedAt.isNull())
                ..orderBy([(t) => OrderingTerm.asc(t.position)]))
              .get();
      before = JournalEntryWithPostings(
        entry: _journalToDomain(existingRow),
        postings: List<Posting>.unmodifiable(
          oldPostingRows.map(_postingToDomain),
        ),
      );

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
      after = (await _liveEntry(id))!;
    });

    return JournalMutationReceipt(before: before, after: after);
  }

  /// Reverses [receipt] only while its complete committed version is current.
  Future<void> undoMutation(JournalMutationReceipt receipt) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await validateUndo(receipt);
      final current = await _liveEntry(receipt.after.entry.id);

      final id = receipt.after.entry.id;
      final postingTombstone = PostingsCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );

      final before = receipt.before;
      if (before == null) {
        await (_db.update(
          _db.journalEntries,
        )..where((t) => t.id.equals(id))).write(
          JournalEntriesCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(stamp.now),
          ),
        );
        await _outbox.enqueue(
          table: JournalEntryRepository._journalTable,
          rowId: id,
        );
        await (_db.update(_db.postings)
              ..where((t) => t.journalEntryId.equals(id))
              ..where((t) => t.deletedAt.isNull()))
            .write(postingTombstone);
        for (final posting in current!.postings) {
          await _outbox.enqueue(
            table: JournalEntryRepository._postingsTable,
            rowId: posting.id,
          );
        }
        return;
      }

      await (_db.update(
        _db.journalEntries,
      )..where((t) => t.id.equals(id))).write(
        JournalEntriesCompanion(
          date: Value(before.entry.date),
          settledOn: Value(before.entry.settledOn),
          narration: Value(before.entry.narration),
          payee: Value(before.entry.payee),
          flag: Value(before.entry.flag),
          tagIdsJson: Value(jsonEncode(before.entry.tagIds)),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
          deletedAt: const Value(null),
        ),
      );
      await _outbox.enqueue(
        table: JournalEntryRepository._journalTable,
        rowId: id,
      );

      await (_db.update(_db.postings)
            ..where((t) => t.journalEntryId.equals(id))
            ..where((t) => t.deletedAt.isNull()))
          .write(postingTombstone);
      for (final posting in current!.postings) {
        await _outbox.enqueue(
          table: JournalEntryRepository._postingsTable,
          rowId: posting.id,
        );
      }

      for (final prior in before.postings) {
        final restored = Posting(
          id: _uuid.v4(),
          journalEntryId: id,
          position: prior.position,
          accountId: prior.accountId,
          units: prior.units,
          unit: prior.unit,
          cost: prior.cost,
          price: prior.price,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        );
        await _db.into(_db.postings).insert(_postingCompanion(restored));
        await _outbox.enqueue(
          table: JournalEntryRepository._postingsTable,
          rowId: restored.id,
        );
      }
    });
  }

  /// Verifies the complete JE and every live posting without writing.
  Future<void> validateUndo(JournalMutationReceipt receipt) async {
    final current = await _liveEntry(receipt.after.entry.id);
    if (!_sameEntry(current, receipt.after)) {
      throw JournalMutationConflict(
        'Journal entry ${receipt.after.entry.id} changed after commit.',
      );
    }
  }

  Future<JournalEntryWithPostings?> _liveEntry(String id) async {
    final entryRow = await (_db.select(
      _db.journalEntries,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (entryRow == null) return null;
    final postingRows =
        await (_db.select(_db.postings)
              ..where((t) => t.journalEntryId.equals(id) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return JournalEntryWithPostings(
      entry: _journalToDomain(entryRow),
      postings: List<Posting>.unmodifiable(postingRows.map(_postingToDomain)),
    );
  }

  bool _sameEntry(
    JournalEntryWithPostings? current,
    JournalEntryWithPostings expected,
  ) {
    if (current == null) return false;
    final currentEntry = current.entry;
    final expectedEntry = expected.entry;
    if (currentEntry.id != expectedEntry.id ||
        !currentEntry.date.isAtSameMomentAs(expectedEntry.date) ||
        !_sameInstant(currentEntry.settledOn, expectedEntry.settledOn) ||
        currentEntry.narration != expectedEntry.narration ||
        currentEntry.payee != expectedEntry.payee ||
        !_sameStrings(currentEntry.tagIds, expectedEntry.tagIds) ||
        currentEntry.flag != expectedEntry.flag ||
        !_sameVersion(currentEntry.sync, expectedEntry.sync)) {
      return false;
    }
    if (current.postings.length != expected.postings.length) return false;
    for (var i = 0; i < current.postings.length; i++) {
      final actual = current.postings[i];
      final committed = expected.postings[i];
      if (actual.id != committed.id ||
          actual.journalEntryId != committed.journalEntryId ||
          actual.position != committed.position ||
          actual.accountId != committed.accountId ||
          actual.units != committed.units ||
          actual.unit != committed.unit ||
          actual.cost != committed.cost ||
          actual.price != committed.price ||
          !_sameVersion(actual.sync, committed.sync)) {
        return false;
      }
    }
    return true;
  }

  bool _sameVersion(SyncMeta actual, SyncMeta committed) =>
      actual.ownerUserId == committed.ownerUserId &&
      actual.updatedByDevice == committed.updatedByDevice &&
      actual.updatedAt.isAtSameMomentAs(committed.updatedAt) &&
      actual.hlc == committed.hlc &&
      _sameInstant(actual.deletedAt, committed.deletedAt);

  bool _sameInstant(DateTime? left, DateTime? right) => left == null
      ? right == null
      : right != null && left.isAtSameMomentAs(right);

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
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
