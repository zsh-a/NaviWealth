/// Cross-domain seam for the per-chat-turn ContextPack + AiTrace seed
/// (`docs/lifeos-shell.md` §4, D-1.6b).
///
/// `ChatRepository` consults [chatTracePrepProvider] before sending each
/// turn so it can stamp the wire context + transparency trace from
/// whichever domain owns the current build. The shell default returns
/// `null`, in which case the repository skips the trace seam — chat
/// itself never blocks on this layer.
///
/// FinanceOS currently supplies `financeChatTracePrepProvider`. Other
/// domains can add their own trace prep through the app composition root
/// when their chat context needs to join this per-turn seed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/ai_trace.dart' show AiTrace;
import '../contracts/contracts.dart' show ContextPack;

/// Output of [ChatTracePrep]: the [ContextPack] sent on the wire and
/// the seed [AiTrace] that the repository finalises after the stream
/// closes. Any field may be `null` if the active domain chose not to
/// wire AI tracing for this turn.
typedef ChatTracePrepResult = ({
  ContextPack? pack,
  AiTrace? traceSeed,
  bool traceVerbose,
});

/// Closure that builds the per-request ContextPack + AiTrace seed.
/// Domain composition provides it as a Riverpod provider so it can
/// close over `Ref` without forcing repository constructors to depend
/// on Riverpod directly.
typedef ChatTracePrep =
    Future<ChatTracePrepResult> Function({
      required String requestId,
      required String userMessage,
    });

/// Active trace-prep closure for the current build. Default is `null`
/// (no preparer registered); `ChatRepository` falls back to its
/// no-context path in that case.
final chatTracePrepProvider = Provider<ChatTracePrep?>((ref) => null);
