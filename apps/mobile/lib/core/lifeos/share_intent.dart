/// Domain-neutral share-intent contract used by the LifeOS shell.
///
/// App code owns platform plugin integration. Domains own the business write
/// path for payloads they understand.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SharedIntentKind { text, url, image, file, other }

class SharedIntentPayload {
  const SharedIntentPayload({
    required this.kind,
    required this.value,
    this.mimeType,
    this.message,
  });

  /// Text/url content or the local file path copied by the platform plugin.
  final SharedIntentKind kind;
  final String value;
  final String? mimeType;
  final String? message;

  bool get isTextual =>
      kind == SharedIntentKind.text || kind == SharedIntentKind.url;
}

class DomainShareIntentResult {
  const DomainShareIntentResult({
    required this.destinationPath,
    this.navigationPriority = 0,
  });

  /// App route to open after a batch contains at least one handled payload.
  final String destinationPath;

  /// Higher value wins when one batch handles payloads in multiple domains.
  final int navigationPriority;
}

abstract class DomainShareIntentHandler {
  const DomainShareIntentHandler({this.priority = 0});

  /// Higher value gets first chance to handle a payload.
  final int priority;

  Future<DomainShareIntentResult?> handle(Ref ref, SharedIntentPayload payload);
}
