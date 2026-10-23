/// App-owned trace preparation, independent from domain context retrieval.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/ai_trace.dart' show AiTrace;

typedef ChatTracePrepResult = ({AiTrace? traceSeed, bool traceVerbose});

typedef ChatTracePrep = Future<ChatTracePrepResult> Function({
  required String requestId,
  required String userMessage,
});

/// The application supplies trace policy; domain packs contribute context only.
final chatTracePrepProvider = Provider<ChatTracePrep?>((ref) => null);
