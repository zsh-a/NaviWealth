part of 'recurring_transaction_repository.dart';

class RecurringMaterialisationService {
  RecurringMaterialisationService({
    required RecurringTransactionRepository recurringRepository,
    required JournalEntryRepository journalEntryRepository,
    RecurrenceEngine recurrenceEngine = const RecurrenceEngine(),
  }) : _recurringRepository = recurringRepository,
       _journalEntryRepository = journalEntryRepository,
       _recurrenceEngine = recurrenceEngine;

  final RecurringTransactionRepository _recurringRepository;
  final JournalEntryRepository _journalEntryRepository;
  final RecurrenceEngine _recurrenceEngine;

  Future<int> materialiseDue(DateTime now, {int maxOccurrences = 100}) async {
    var materialised = 0;
    final due = await _recurringRepository.dueAt(now);
    for (final tx in due) {
      var current = tx;
      var guard = 0;
      final rule = _recurrenceEngine.parse(current.rrule);
      while (!current.nextDueAt.isAfter(now) && guard < maxOccurrences) {
        final occurrence = current.nextDueAt;
        final until = rule.until;
        if (until != null && occurrence.isAfter(until)) {
          await _recurringRepository.update(current.id, enabled: false);
          break;
        }
        final journalId = journalEntryId(
          recurringTransactionId: current.id,
          occurrenceDate: occurrence,
        );
        final existing = await _journalEntryRepository.getById(journalId);
        if (existing == null) {
          final template = JournalBuildTemplateCodec.decode(
            current.templateJournalBuildJson,
          );
          await _journalEntryRepository.create(
            entry: template.entryForOccurrence(occurrence, id: journalId),
            postings: template.postings,
          );
          materialised++;
        }
        final nextDueAt = _recurrenceEngine.nextAfter(rule, occurrence);
        current = await _recurringRepository.markMaterialised(
          id: current.id,
          occurrenceDate: occurrence,
          nextDueAt: nextDueAt,
        );
        if (until != null && nextDueAt.isAfter(until)) {
          await _recurringRepository.update(current.id, enabled: false);
          break;
        }
        guard++;
      }
    }
    return materialised;
  }

  static String journalEntryId({
    required String recurringTransactionId,
    required DateTime occurrenceDate,
  }) {
    return 'recurring:$recurringTransactionId:${_yyyymmdd(occurrenceDate)}';
  }

  static String _yyyymmdd(DateTime value) {
    final date = DateTime.utc(value.year, value.month, value.day);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}${two(date.month)}${two(date.day)}';
  }
}
