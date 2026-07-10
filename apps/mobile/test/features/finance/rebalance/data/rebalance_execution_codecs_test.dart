import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_execution_codecs.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';

import 'rebalance_execution_test_fixtures.dart';

void main() {
  test('plan v1 roundtrips through canonical strict JSON', () {
    final encoded = RebalancePlanCodec.encode(testPlan());
    final decoded = RebalancePlanCodec.decode(encoded);

    expect(RebalancePlanCodec.encode(decoded), encoded);
  });

  test('request v1 roundtrips every canonical account and asset field', () {
    final request = testRequest('tx-1');
    final encoded = RebalanceExecutionRequestCodec.encode(request);
    final decoded = RebalanceExecutionRequestCodec.decode(encoded);

    expect(decoded, request);
    expect(RebalanceExecutionRequestCodec.encode(decoded), encoded);
  });

  test(
    'receipt v1 roundtrips complete journal, posting, price, and sync data',
    () {
      final encoded = TradeMutationReceiptCodec.encode(testReceipt('tx-1'));
      final decoded = TradeMutationReceiptCodec.decode(encoded);

      expect(decoded.transactionId, 'tx-1');
      expect(decoded.journal.before, isNotNull);
      expect(decoded.journal.after.postings, hasLength(2));
      expect(decoded.price?.before, isNotNull);
      expect(TradeMutationReceiptCodec.encode(decoded), encoded);
    },
  );

  test('all versioned codecs reject unknown versions', () {
    final raws = [
      RebalancePlanCodec.encode(testPlan()),
      RebalanceExecutionRequestCodec.encode(testRequest('tx-1')),
      TradeMutationReceiptCodec.encode(testReceipt('tx-1')),
    ];

    for (final raw in raws) {
      final json = jsonDecode(raw) as Map<String, Object?>;
      json['version'] = 2;
      expect(
        () => _decodeByKind(jsonEncode(json)),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
    }
  });

  test('fixed v1 shapes reject unknown fields at every boundary', () {
    final envelope = _json(RebalancePlanCodec.encode(testPlan()));
    envelope['future'] = true;

    final requestAccount = _json(
      RebalanceExecutionRequestCodec.encode(testRequest('tx-1')),
    );
    (_payload(requestAccount)['account']! as Map<String, Object?>)['future'] =
        true;

    final requestSync = _json(
      RebalanceExecutionRequestCodec.encode(testRequest('tx-1')),
    );
    final account = _payload(requestSync)['account']! as Map<String, Object?>;
    (account['sync']! as Map<String, Object?>)['future'] = true;

    final receiptPosting = _json(
      TradeMutationReceiptCodec.encode(testReceipt('tx-1')),
    );
    final journal =
        _payload(receiptPosting)['journal']! as Map<String, Object?>;
    final after = journal['after']! as Map<String, Object?>;
    ((after['postings']! as List).first as Map<String, Object?>)['future'] =
        true;

    final receiptPrice = _json(
      TradeMutationReceiptCodec.encode(testReceipt('tx-1')),
    );
    final price = _payload(receiptPrice)['price']! as Map<String, Object?>;
    (price['after']! as Map<String, Object?>)['future'] = true;

    final planTarget = _json(RebalancePlanCodec.encode(testPlan()));
    (_payload(planTarget)['target']! as Map<String, Object?>)['future'] = true;

    final planSuggestion = _json(RebalancePlanCodec.encode(testPlan()));
    ((_payload(planSuggestion)['trades']! as List).first
            as Map<String, Object?>)['future'] =
        true;

    final cases = <(String, Object Function())>[
      (
        jsonEncode(envelope),
        () => RebalancePlanCodec.decode(jsonEncode(envelope)),
      ),
      (
        jsonEncode(requestAccount),
        () => RebalanceExecutionRequestCodec.decode(jsonEncode(requestAccount)),
      ),
      (
        jsonEncode(requestSync),
        () => RebalanceExecutionRequestCodec.decode(jsonEncode(requestSync)),
      ),
      (
        jsonEncode(receiptPosting),
        () => TradeMutationReceiptCodec.decode(jsonEncode(receiptPosting)),
      ),
      (
        jsonEncode(receiptPrice),
        () => TradeMutationReceiptCodec.decode(jsonEncode(receiptPrice)),
      ),
      (
        jsonEncode(planTarget),
        () => RebalancePlanCodec.decode(jsonEncode(planTarget)),
      ),
      (
        jsonEncode(planSuggestion),
        () => RebalancePlanCodec.decode(jsonEncode(planSuggestion)),
      ),
    ];
    for (final (_, decode) in cases) {
      expect(decode, throwsA(isA<RebalanceExecutionCodecError>()));
    }
  });

  test(
    'missing fields, wrong types, enum, Decimal, HLC, and UTC fail closed',
    () {
      final missing = _json(RebalancePlanCodec.encode(testPlan()));
      (_payload(missing)).remove('totalAssets');

      final wrongType = _json(
        RebalanceExecutionRequestCodec.encode(testRequest('tx-1')),
      );
      _payload(wrongType)['quantity'] = 1.25;

      final invalidEnum = _json(RebalancePlanCodec.encode(testPlan()));
      ((_payload(invalidEnum)['trades']! as List).first
              as Map<String, Object?>)['direction'] =
          'hold';

      final invalidDecimal = _json(RebalancePlanCodec.encode(testPlan()));
      _payload(invalidDecimal)['driftBeforePct'] = 'not-a-decimal';

      final invalidHlc = _json(
        TradeMutationReceiptCodec.encode(testReceipt('tx-1')),
      );
      final receiptPayload = _payload(invalidHlc);
      final assetAfter = receiptPayload['assetAfter']! as Map<String, Object?>;
      (assetAfter['sync']! as Map<String, Object?>)['hlc'] = 'broken';

      final nonUtc = _json(
        RebalanceExecutionRequestCodec.encode(testRequest('tx-1')),
      );
      _payload(nonUtc)['tradeDate'] = '2026-07-10T08:00:00+08:00';

      final inconsistentReceipt = _json(
        TradeMutationReceiptCodec.encode(testReceipt('tx-1')),
      );
      _payload(inconsistentReceipt)['transactionId'] = 'other-tx';

      expect(
        () => RebalancePlanCodec.decode(jsonEncode(missing)),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
      expect(
        () => RebalanceExecutionRequestCodec.decode(jsonEncode(wrongType)),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
      expect(
        () => RebalancePlanCodec.decode(jsonEncode(invalidEnum)),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
      expect(
        () => RebalancePlanCodec.decode(jsonEncode(invalidDecimal)),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
      expect(
        () => TradeMutationReceiptCodec.decode(jsonEncode(invalidHlc)),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
      expect(
        () => RebalanceExecutionRequestCodec.decode(jsonEncode(nonUtc)),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
      expect(
        () => TradeMutationReceiptCodec.decode(jsonEncode(inconsistentReceipt)),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
    },
  );

  test('encoders reject non-UTC canonical times', () {
    final local = DateTime(2026, 7, 10, 8);

    expect(
      () => RebalanceExecutionRequestCodec.encode(
        testRequest('tx-1', tradeDate: local),
      ),
      throwsA(isA<RebalanceExecutionCodecError>()),
    );
    expect(
      () => TradeMutationReceiptCodec.encode(
        testReceipt('tx-1', entryDate: local),
      ),
      throwsA(isA<RebalanceExecutionCodecError>()),
    );
  });

  test(
    'fingerprint ignores incidental ordering and changes with economics',
    () {
      final first = RebalancePlanFingerprint.compute(testPlan());
      final reordered = RebalancePlanFingerprint.compute(
        testPlan(reverseCollections: true),
      );
      final rescaled = RebalancePlanFingerprint.compute(
        testPlan(buyAmount: Decimal.parse('100.00')),
      );
      final changed = RebalancePlanFingerprint.compute(
        testPlan(buyAmount: Decimal.fromInt(101)),
      );

      expect(first, startsWith('rebalance-plan/v1:'));
      expect(reordered, first);
      expect(rescaled, first);
      expect(changed, isNot(first));
    },
  );

  test(
    'execution state constructor rejects invalid persisted combinations',
    () {
      expect(
        () => RebalanceExecutionItem(
          id: 'tx-1',
          sessionId: 'session-1',
          ownerUserId: 'owner-a',
          position: 0,
          suggestion: testPlan().trades.first,
          state: RebalanceExecutionItemState.ready,
          createdAt: testNow,
          updatedAt: testNow,
        ),
        throwsA(isA<RebalanceExecutionInvariantError>()),
      );
      expect(
        () => RebalanceExecutionItem(
          id: 'tx-1',
          sessionId: 'session-1',
          ownerUserId: 'owner-a',
          position: 0,
          suggestion: testPlan().trades.first,
          request: testRequest('tx-1'),
          state: RebalanceExecutionItemState.undoFailed,
          createdAt: testNow,
          updatedAt: testNow,
        ),
        throwsA(isA<RebalanceExecutionInvariantError>()),
      );
      expect(
        () => RebalanceExecutionItem(
          id: 'tx-1',
          sessionId: 'session-1',
          ownerUserId: 'owner-a',
          position: 0,
          suggestion: testPlan().trades.first,
          state: RebalanceExecutionItemState.recoveryBlocked,
          recoveryWasApplied: true,
          createdAt: testNow,
          updatedAt: testNow,
        ),
        throwsA(isA<RebalanceExecutionInvariantError>()),
      );
    },
  );
}

Map<String, Object?> _json(String raw) =>
    jsonDecode(raw) as Map<String, Object?>;

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    envelope['payload']! as Map<String, Object?>;

Object _decodeByKind(String raw) {
  final json = _json(raw);
  return switch (json['kind']) {
    'rebalancePlan' => RebalancePlanCodec.decode(raw),
    'rebalanceExecutionRequest' => RebalanceExecutionRequestCodec.decode(raw),
    'tradeMutationReceipt' => TradeMutationReceiptCodec.decode(raw),
    _ => throw StateError('Unexpected fixture kind.'),
  };
}
