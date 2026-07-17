import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/statement_ingest_parser.dart';

const _fixtureDirectory = 'test/fixtures/finance/ingest';
const _manifestSuffix = '.expected.json';

void main() {
  final directory = Directory(_fixtureDirectory);
  final manifests =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith(_manifestSuffix))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  test(
    'every representative statement has exactly one expectation manifest',
    () {
      final fixtureNames = directory
          .listSync()
          .whereType<File>()
          .map((file) => _basename(file.path))
          .where(
            (name) =>
                name.endsWith('.csv') ||
                name.endsWith('.tsv') ||
                name.endsWith('.txt'),
          )
          .toSet();
      final declaredNames = manifests
          .map(_readManifest)
          .map((manifest) => _requiredString(manifest, 'fixture'))
          .toSet();

      expect(manifests, isNotEmpty);
      expect(declaredNames, fixtureNames);
      expect(declaredNames, hasLength(manifests.length));
    },
  );

  for (final manifestFile in manifests) {
    final manifest = _readManifest(manifestFile);
    final fixtureName = _requiredString(manifest, 'fixture');

    test('$fixtureName matches its privacy-safe parse contract', () {
      expect(_requiredInt(manifest, 'schemaVersion'), 1);
      final privacy = _requiredMap(manifest, 'privacy');
      expect(_requiredBool(privacy, 'containsUserData'), isFalse);
      expect(_requiredStringList(privacy, 'diagnosticFields'), [
        'lineNumber',
        'code',
      ]);

      final raw = File('$_fixtureDirectory/$fixtureName');
      expect(raw.existsSync(), isTrue, reason: 'Missing fixture $fixtureName');
      final report = parseStatementLedgerReport(
        raw.readAsStringSync(),
        defaultCurrency: _requiredString(manifest, 'defaultCurrency'),
      );
      final expected = _requiredMap(manifest, 'expected');

      expect(report.provider.name, _requiredString(expected, 'provider'));
      expect(
        report.ledger.candidateRowCount,
        _requiredInt(expected, 'candidateRowCount'),
      );
      expect(report.rows.length, _requiredInt(expected, 'acceptedRowCount'));
      expect(
        report.ledger.skippedRowCount,
        _requiredInt(expected, 'skippedRowCount'),
      );
      expect(
        report.ledger.diagnosticsComplete,
        _requiredBool(expected, 'diagnosticsComplete'),
      );
      expect(
        report.ledger.accountsForEveryCandidate,
        _requiredBool(expected, 'accountsForEveryCandidate'),
      );
      expect(
        report.rows
            .map(
              (row) => <String, Object?>{
                'occurredAt': row.occurredAt.toUtc().toIso8601String(),
                'description': row.description,
                'amountMinor': row.amountMinor,
                'currency': row.currency,
                'kind': row.kind.name,
                'categoryHint': row.categoryHint,
              },
            )
            .toList(),
        _requiredMapList(expected, 'rows'),
      );
      expect(
        report.ledger.issues
            .map(
              (issue) => <String, Object?>{
                'lineNumber': issue.lineNumber,
                'code': issue.code.name,
              },
            )
            .toList(),
        _requiredMapList(expected, 'issues'),
      );
    });
  }
}

Map<String, Object?> _readManifest(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Manifest root must be an object: ${file.path}');
  }
  return decoded;
}

Map<String, Object?> _requiredMap(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('$key must be an object');
  }
  return value;
}

List<Map<String, Object?>> _requiredMapList(
  Map<String, Object?> map,
  String key,
) {
  final value = map[key];
  if (value is! List<Object?> ||
      value.any((element) => element is! Map<String, Object?>)) {
    throw FormatException('$key must be an array of objects');
  }
  return value.cast<Map<String, Object?>>();
}

List<String> _requiredStringList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List<Object?> || value.any((element) => element is! String)) {
    throw FormatException('$key must be an array of strings');
  }
  return value.cast<String>();
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

int _requiredInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

bool _requiredBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

String _basename(String path) => path.split(Platform.pathSeparator).last;
