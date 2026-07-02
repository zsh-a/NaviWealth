part of 'journal_entry_builders.dart';

/// Output of a [JournalEntryBuilders] call: a `(entry, postings)` pair
/// the caller hands straight to [JournalEntryRepository.create].
class JournalEntryBuild {
  const JournalEntryBuild({required this.entry, required this.postings});

  final JournalEntryDraft entry;
  final List<PostingDraft> postings;
}
