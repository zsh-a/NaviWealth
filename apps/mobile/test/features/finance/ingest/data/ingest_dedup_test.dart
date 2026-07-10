import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_dedup.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

ParsedTransaction _parsed({
  String description = 'Starbucks Coffee',
  int amountMinor = -3800,
  String currency = 'CNY',
  DateTime? at,
}) => ParsedTransaction(
  description: description,
  amountMinor: amountMinor,
  currency: currency,
  occurredAt: at ?? DateTime.utc(2026, 5, 10),
);

TransactionInput _existing({
  String id = 'e1',
  String description = 'Starbucks Coffee',
  String amountMinor = '-3800',
  String currency = 'CNY',
  DateTime? at,
}) => TransactionInput(
  id: id,
  description: description,
  amountMinor: amountMinor,
  currency: currency,
  occurredAt: at ?? DateTime.utc(2026, 5, 10),
);

IndexedDedupResult<String> _indexed(
  ParsedTransaction parsed,
  List<TransactionInput> existing, {
  Duration window = kIngestDedupWindow,
  IngestDedupMetrics? metrics,
}) {
  final index = IngestDedupIndex<String>(window: window);
  for (final entry in existing) {
    index.add(entry, entry.id);
  }
  return index.match(parsed, metrics: metrics);
}

void main() {
  group('classifyDedup', () {
    test('exact merchant + amount + window → duplicate', () {
      final r = classifyDedup(_parsed(), [_existing()]);
      expect(r.verdict, DedupVerdict.duplicate);
      expect(r.targetEntryId, 'e1');
    });

    test('same amount + same calendar day with empty key → newTxn', () {
      final r = classifyDedup(_parsed(description: ''), [
        _existing(description: ''),
      ]);
      expect(r.verdict, DedupVerdict.newTxn);
    });

    test('same amount + same day but different merchant → newTxn', () {
      final r = classifyDedup(
        _parsed(description: 'Blue Bottle', amountMinor: -3800),
        [_existing(description: 'Starbucks Coffee', amountMinor: '-3800')],
      );
      expect(r.verdict, DedupVerdict.newTxn);
    });

    test('same first word but different descriptor → newTxn', () {
      final r = classifyDedup(
        _parsed(description: 'Apple Store', amountMinor: -6800),
        [_existing(description: 'Apple Music', amountMinor: '-6800')],
      );
      expect(r.verdict, DedupVerdict.newTxn);
    });

    test('same merchant + near amount within tolerance → likely', () {
      final r = classifyDedup(_parsed(amountMinor: -3800), [
        _existing(amountMinor: '-3850'),
      ]);
      expect(r.verdict, DedupVerdict.likelyDuplicate);
      expect(r.targetEntryId, 'e1');
    });

    test('different merchant and amount → newTxn', () {
      final r = classifyDedup(
        _parsed(description: 'Uber Ride', amountMinor: -2200),
        [_existing()],
      );
      expect(r.verdict, DedupVerdict.newTxn);
      expect(r.targetEntryId, isNull);
    });

    test('outside the date window → newTxn', () {
      final r = classifyDedup(_parsed(at: DateTime.utc(2026, 5, 20)), [
        _existing(at: DateTime.utc(2026, 5, 10)),
      ]);
      expect(r.verdict, DedupVerdict.newTxn);
    });

    test('currency mismatch is never a duplicate', () {
      final r = classifyDedup(_parsed(currency: 'USD'), [
        _existing(currency: 'CNY'),
      ]);
      expect(r.verdict, DedupVerdict.newTxn);
    });

    test('opposite sign is never a duplicate', () {
      final r = classifyDedup(_parsed(), [_existing(amountMinor: '3800')]);
      expect(r.verdict, DedupVerdict.newTxn);
    });

    test('zero amount is always fresh', () {
      final r = classifyDedup(_parsed(amountMinor: 0), [_existing()]);
      expect(r.verdict, DedupVerdict.newTxn);
    });
  });

  group('IngestDedupIndex', () {
    test('normalized exact description is not constrained by merchant key', () {
      final parsed = _parsed(description: 'STAR-BUCKS 1');
      final result = _indexed(parsed, [_existing(description: 'STARBUCKS 1')]);

      expect(result.verdict, DedupVerdict.duplicate);
      expect(result.target, 'e1');
    });

    test('exact amount wins over earlier likely and keeps earliest exact', () {
      final result = _indexed(_parsed(), [
        _existing(id: 'likely', amountMinor: '-3850'),
        _existing(id: 'exact-first'),
        _existing(id: 'exact-later'),
      ]);

      expect(result.verdict, DedupVerdict.duplicate);
      expect(result.target, 'exact-first');
    });

    test('earliest likely target wins across amount and day buckets', () {
      final result = _indexed(_parsed(), [
        _existing(
          id: 'first',
          amountMinor: '-3850',
          at: DateTime.utc(2026, 5, 11),
        ),
        _existing(
          id: 'later',
          amountMinor: '-3750',
          at: DateTime.utc(2026, 5, 9),
        ),
      ]);

      expect(result.verdict, DedupVerdict.likelyDuplicate);
      expect(result.target, 'first');
    });

    test('uses exact instant window across UTC days and custom windows', () {
      final parsed = _parsed(at: DateTime.utc(2026, 5, 11, 0, 30));
      final inside = _existing(at: DateTime.utc(2026, 5, 10, 23, 30));
      final boundary = _existing(
        id: 'boundary',
        at: parsed.occurredAt.subtract(const Duration(hours: 2)),
      );
      final outside = _existing(
        id: 'outside',
        at: parsed.occurredAt.subtract(
          const Duration(hours: 2, microseconds: 1),
        ),
      );

      expect(
        _indexed(parsed, [inside], window: const Duration(hours: 1)).target,
        'e1',
      );
      expect(
        _indexed(parsed, [boundary], window: const Duration(hours: 2)).target,
        'boundary',
      );
      expect(
        _indexed(parsed, [outside], window: const Duration(hours: 2)).verdict,
        DedupVerdict.newTxn,
      );
    });

    test('keeps the default 72-hour boundary inclusive to the microsecond', () {
      final parsed = _parsed();
      final boundary = _existing(
        id: 'boundary',
        at: parsed.occurredAt.subtract(const Duration(hours: 72)),
      );
      final outside = _existing(
        id: 'outside',
        at: parsed.occurredAt.subtract(
          const Duration(hours: 72, microseconds: 1),
        ),
      );

      expect(_indexed(parsed, [boundary]).target, 'boundary');
      expect(_indexed(parsed, [outside]).verdict, DedupVerdict.newTxn);
    });

    test('handles zoned instants, currency case, sign and invalid rows', () {
      final parsed = _parsed(
        currency: 'cny',
        at: DateTime.parse('2026-05-11T00:30:00+08:00'),
      );
      final result = _indexed(parsed, [
        _existing(id: 'invalid', amountMinor: 'not-an-amount'),
        _existing(id: 'zero', amountMinor: '0'),
        _existing(id: 'credit', amountMinor: '3800', currency: 'CNY'),
        _existing(
          id: 'match',
          currency: 'CNY',
          at: DateTime.parse('2026-05-10T16:30:00Z'),
        ),
      ]);

      expect(result.verdict, DedupVerdict.duplicate);
      expect(result.target, 'match');
    });

    test('preserves fixed-minor and asymmetric one-percent boundaries', () {
      expect(
        _indexed(_parsed(amountMinor: -3800), [
          _existing(amountMinor: '-3900'),
        ]).verdict,
        DedupVerdict.likelyDuplicate,
      );
      expect(
        _indexed(_parsed(amountMinor: -3800), [
          _existing(amountMinor: '-3901'),
        ]).verdict,
        DedupVerdict.newTxn,
      );
      expect(
        _indexed(_parsed(amountMinor: -10000), [
          _existing(amountMinor: '-10101'),
        ]).verdict,
        DedupVerdict.likelyDuplicate,
      );
      expect(
        _indexed(_parsed(amountMinor: -10101), [
          _existing(amountMinor: '-10000'),
        ]).verdict,
        DedupVerdict.likelyDuplicate,
      );
      expect(
        _indexed(_parsed(amountMinor: -10000), [
          _existing(amountMinor: '-10102'),
        ]).verdict,
        DedupVerdict.newTxn,
      );
    });

    test('prefilter preserves floating-point tolerance at large integers', () {
      final parsed = _parsed(amountMinor: -9000000000000000000);
      final existing = _existing(amountMinor: '-9090909090909090911');
      final reference = classifyDedup(parsed, [existing]);
      final indexed = _indexed(parsed, [existing]);

      expect(reference.verdict, DedupVerdict.likelyDuplicate);
      expect(
        (indexed.verdict, indexed.target),
        (reference.verdict, reference.targetEntryId),
      );
    });

    test('saturates custom windows at DateTime bounds', () {
      final parsed = _parsed(
        at: DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true),
      );
      final existing = _existing(at: parsed.occurredAt);

      expect(
        _indexed(parsed, [existing], window: const Duration(days: 1)).target,
        'e1',
      );
    });

    test('matches the linear reference over 10k dynamic classifications', () {
      final random = Random(0x1a6e57);
      const descriptions = <String>[
        'STAR-BUCKS 1',
        'STARBUCKS 1',
        'Netflix',
        'Blue Bottle',
        'Apple Music',
        'Apple Store',
        '',
      ];
      const currencies = <String>['CNY', 'cny', 'USD'];

      for (var scenario = 0; scenario < 100; scenario++) {
        final ledger = <TransactionInput>[];
        final index = IngestDedupIndex<String>();
        for (var step = 0; step < 100; step++) {
          final magnitude = 1000 + random.nextInt(200000);
          final signed = random.nextBool() ? magnitude : -magnitude;
          final parsed = _parsed(
            description: descriptions[random.nextInt(descriptions.length)],
            amountMinor: signed,
            currency: currencies[random.nextInt(currencies.length)],
            at: DateTime.utc(2026, 5, 1).add(
              Duration(
                hours: random.nextInt(24 * 14),
                minutes: random.nextInt(60),
              ),
            ),
          );
          final reference = classifyDedup(parsed, ledger);
          final indexed = index.match(parsed);
          expect(
            (indexed.verdict, indexed.target),
            (reference.verdict, reference.targetEntryId),
            reason: 'scenario=$scenario step=$step',
          );

          final id = 'row-$scenario-$step';
          final entry = _existing(
            id: id,
            description: parsed.description,
            amountMinor: parsed.amountMinor.toString(),
            currency: parsed.currency,
            at: parsed.occurredAt,
          );
          ledger.add(entry);
          index.add(entry, id);
        }
      }
    });

    test('amount buckets avoid scanning a long otherwise-identical ledger', () {
      final index = IngestDedupIndex<String>();
      for (var i = 0; i < 5000; i++) {
        final entry = _existing(
          id: 'far-$i',
          amountMinor: '${-(1000000 + i * 1000)}',
        );
        index.add(entry, entry.id);
      }
      final matching = _existing(id: 'match');
      index.add(matching, matching.id);
      final metrics = IngestDedupMetrics();

      final result = index.match(_parsed(), metrics: metrics);

      expect(result.target, 'match');
      expect(metrics.candidateVisits, 1);
      expect(metrics.descriptorComparisons, 1);
    });
  });
}
