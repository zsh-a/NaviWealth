import 'dart:convert';

import 'package:crypto/crypto.dart';

String? cleanIngestReference(String? raw) {
  final value = raw?.trim();
  if (value == null ||
      value.isEmpty ||
      const {
        '-',
        '--',
        '/',
        '—',
        'n/a',
        'null',
      }.contains(value.toLowerCase())) {
    return null;
  }
  return value;
}

/// Provider-issued identity, separate from merchant/product descriptions.
/// Only opaque hashes are carried into the confirmed journal's existing tags.
class IngestSourceReference {
  const IngestSourceReference({
    required this.provider,
    required this.transactionId,
    this.account,
  });

  final String provider;
  final String transactionId;
  final String? account;

  /// Bank/broker references may be account-local counters. Alipay/WeChat
  /// transaction ids identify an order throughout their provider namespace.
  bool get hasUniqueScope =>
      cleanIngestReference(account) != null ||
      provider == 'alipay' ||
      provider == 'wechatPay';

  String get scope => _hash([provider, account ?? '']);
  String get identity => _hash([provider, account ?? '', transactionId]);

  IngestSourceReference withProvider(String value) => IngestSourceReference(
    provider: value,
    transactionId: transactionId,
    account: account,
  );

  Map<String, Object?> toJson() => {
    'provider': provider,
    'transaction_id': transactionId,
    if (account != null) 'account': account,
  };

  factory IngestSourceReference.fromJson(Map<String, Object?> json) =>
      IngestSourceReference(
        provider: json['provider']! as String,
        transactionId: json['transaction_id']! as String,
        account: json['account'] as String?,
      );

  static String _hash(List<String> parts) =>
      sha256.convert(utf8.encode(jsonEncode(parts))).toString();
}

const ingestIdentityTagPrefix = 'ingest:identity:v1:';
const ingestScopeTagPrefix = 'ingest:scope:v1:';
const ingestKindTagPrefix = 'ingest:kind:';

String? ingestTagValue(Iterable<String> tags, String prefix) {
  for (final tag in tags) {
    if (tag.startsWith(prefix)) return tag.substring(prefix.length);
  }
  return null;
}

List<String> ingestProvenanceTags({
  required String kind,
  IngestSourceReference? reference,
}) => [
  '$ingestKindTagPrefix$kind',
  if (reference != null && reference.hasUniqueScope) ...[
    '$ingestIdentityTagPrefix${reference.identity}',
    '$ingestScopeTagPrefix${reference.scope}',
  ],
];

List<String> ingestTagsFromPayload(Object? value) {
  if (value is! List) return const [];
  final valid = RegExp(
    r'^ingest:(?:(?:identity|scope):v1:[a-f0-9]{64}|kind:(?:expense|income|transfer|trade))$',
  );
  return [
    for (final tag in value)
      if (tag is String && valid.hasMatch(tag)) tag,
  ];
}
