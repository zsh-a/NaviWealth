/// Device chat runner contract.
///
/// The cloud AI backend was deleted. Production interactive chat is composed
/// in `app/bootstrap.dart` through the FRB-backed `FrbChatRunner`; this file
/// keeps only the runner seam used by `RuntimeRoutingAiChatApiClient` and
/// tests.
library;

import 'package:dio/dio.dart';

import '../../../features/ai_chat/data/ai_chat_api_client.dart';
import '../contracts/contracts.dart';

/// The slice of the device runtime the routing client depends on.
/// An interface so tests can inject a scripted device without a
/// network-bound provider client.
abstract class DeviceChatRunner {
  Stream<AiChatEvent> run({
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  });
}
