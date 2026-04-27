import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Wire format magic for NaviWealth encrypted backup files.
const String backupMagic = 'naviwealth.bak.v1';

/// PBKDF2 iteration count for backup key derivation. Tuned high enough
/// to make brute-forcing weak passphrases costly on commodity hardware
/// while staying tolerable on a 2019-era mobile device. Bump in a new
/// magic version if hardware moves on.
const int backupPbkdf2Iterations = 200000;

/// Sealed payload produced by [BackupCodec.encrypt] and consumed by
/// [BackupCodec.decrypt]. Carries the salt, nonce, and authenticated
/// ciphertext so the recipient can re-derive the key from a passphrase
/// alone — no device-specific secret is required.
class BackupEnvelope {
  const BackupEnvelope({
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.createdAt,
    required this.schemaVersion,
    required this.iterations,
  });

  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
  final DateTime createdAt;
  final int schemaVersion;
  final int iterations;

  Map<String, Object?> toJson() => {
    'magic': backupMagic,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
    'kdf': {
      'alg': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
    },
    'cipher': {'alg': 'aes-gcm-256', 'nonce': base64Encode(nonce)},
    'ciphertext': base64Encode(ciphertext),
    'mac': base64Encode(mac),
  };

  static BackupEnvelope fromJson(Map<String, Object?> json) {
    final magic = json['magic'];
    if (magic != backupMagic) {
      throw FormatException('Unknown backup magic: $magic');
    }
    final kdf = json['kdf'] as Map<String, Object?>;
    final cipher = json['cipher'] as Map<String, Object?>;
    if (kdf['alg'] != 'pbkdf2-sha256') {
      throw FormatException('Unsupported KDF: ${kdf['alg']}');
    }
    if (cipher['alg'] != 'aes-gcm-256') {
      throw FormatException('Unsupported cipher: ${cipher['alg']}');
    }
    return BackupEnvelope(
      salt: base64Decode(kdf['salt']! as String),
      nonce: base64Decode(cipher['nonce']! as String),
      ciphertext: base64Decode(json['ciphertext']! as String),
      mac: base64Decode(json['mac']! as String),
      createdAt: DateTime.parse(json['createdAt']! as String),
      schemaVersion: (json['schemaVersion']! as num).toInt(),
      iterations: (kdf['iterations']! as num).toInt(),
    );
  }

  Uint8List encodeBytes() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  static BackupEnvelope decodeBytes(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    return fromJson(json);
  }
}

class BackupCodec {
  BackupCodec({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  Future<BackupEnvelope> encrypt({
    required String passphrase,
    required Uint8List plaintext,
    required int schemaVersion,
    int iterations = backupPbkdf2Iterations,
    DateTime? now,
  }) async {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final secretKey = await _deriveKey(
      passphrase: passphrase,
      salt: salt,
      iterations: iterations,
    );
    final algo = AesGcm.with256bits();
    final secretBox = await algo.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    return BackupEnvelope(
      salt: salt,
      nonce: nonce,
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      mac: Uint8List.fromList(secretBox.mac.bytes),
      createdAt: (now ?? DateTime.now()).toUtc(),
      schemaVersion: schemaVersion,
      iterations: iterations,
    );
  }

  Future<Uint8List> decrypt({
    required String passphrase,
    required BackupEnvelope envelope,
  }) async {
    final secretKey = await _deriveKey(
      passphrase: passphrase,
      salt: envelope.salt,
      iterations: envelope.iterations,
    );
    final algo = AesGcm.with256bits();
    final secretBox = SecretBox(
      envelope.ciphertext,
      nonce: envelope.nonce,
      mac: Mac(envelope.mac),
    );
    try {
      final plain = await algo.decrypt(secretBox, secretKey: secretKey);
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const BackupAuthenticationException();
    }
  }

  Future<SecretKey> _deriveKey({
    required String passphrase,
    required Uint8List salt,
    required int iterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  Uint8List _randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}

/// Thrown when a backup's MAC fails to verify — typically a wrong
/// passphrase, but also any tampered byte. We deliberately don't
/// distinguish so timing/error-message side channels can't tell an
/// attacker which guess was closer.
class BackupAuthenticationException implements Exception {
  const BackupAuthenticationException();

  @override
  String toString() =>
      'Backup authentication failed (wrong passphrase or corrupt file).';
}
