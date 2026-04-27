import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:naviwealth/core/backup/backup_codec.dart';

void main() {
  group('BackupCodec', () {
    final codec = BackupCodec();

    test('encrypt -> decrypt round-trips with the right passphrase', () async {
      final plaintext = Uint8List.fromList(
        utf8.encode('hello, NaviWealth — 你好'),
      );

      final envelope = await codec.encrypt(
        passphrase: 'a-strong-passphrase',
        plaintext: plaintext,
        schemaVersion: 1,
        iterations: 1000, // fast for tests
      );
      final decoded = await codec.decrypt(
        passphrase: 'a-strong-passphrase',
        envelope: envelope,
      );

      expect(decoded, plaintext);
    });

    test('decrypt with the wrong passphrase throws', () async {
      final plaintext = Uint8List.fromList([1, 2, 3, 4]);
      final envelope = await codec.encrypt(
        passphrase: 'right',
        plaintext: plaintext,
        schemaVersion: 1,
        iterations: 1000,
      );

      expect(
        () => codec.decrypt(passphrase: 'wrong', envelope: envelope),
        throwsA(isA<BackupAuthenticationException>()),
      );
    });

    test('envelope serializes through JSON without losing fields', () async {
      final envelope = await codec.encrypt(
        passphrase: 'pw',
        plaintext: Uint8List.fromList([42]),
        schemaVersion: 7,
        iterations: 1000,
        now: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );

      final bytes = envelope.encodeBytes();
      final round = BackupEnvelope.decodeBytes(bytes);

      expect(round.salt, envelope.salt);
      expect(round.nonce, envelope.nonce);
      expect(round.ciphertext, envelope.ciphertext);
      expect(round.mac, envelope.mac);
      expect(round.schemaVersion, 7);
      expect(round.iterations, 1000);
      expect(round.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('rejects unknown magic on decode', () {
      final corrupt = utf8.encode('{"magic":"something-else"}');
      expect(
        () => BackupEnvelope.decodeBytes(Uint8List.fromList(corrupt)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty passphrase', () async {
      expect(
        () => codec.encrypt(
          passphrase: '',
          plaintext: Uint8List(0),
          schemaVersion: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
