part of 'chat_repository.dart';

mixin _ChatRepositorySend {
  ChatHistoryStore get _store;
  AiChatApiClient get _api;
  AuthSessionReader get _sessionReader;
  Future<Map<String, Object?>?> Function()? get _portfolioSnapshotReader;
  ChatTracePrep? get _tracePrep;
  AiTraceStore? get _traceStore;
  void Function(AiTrace finalized)? get _onTraceFinalized;
  Uuid get _uuid;

  Future<void> insertSystemNotice({
    required String sessionId,
    required String ownerUserId,
    required String content,
  });

  /// Send [content] as the next user turn in [sessionId] and stream the
  /// assistant's response. Returns when the stream terminates (either
  /// `done`, an error, or [cancelToken] firing).
  ///
  /// Side effects:
  ///   1. Persist the user turn.
  ///   2. Persist a placeholder assistant turn in `streaming` state.
  ///   3. As each SSE frame arrives, mutate the placeholder and call
  ///      `updateMessage` so subscribers see the text grow.
  ///   4. On `done`, mark the assistant turn `complete`. On `error` /
  ///      stream failure, mark it `errored` and store the message.
  ///   5. Bump the session's `last_message_at`.
  ///   6. If the session title is still the default, autotitle it from
  ///      the first user turn (first ~24 chars of the prompt).
  Future<SendOutcome> sendMessage({
    required String sessionId,
    required String ownerUserId,
    required String content,
    String? systemContext,
    String? model,
    CancelToken? cancelToken,
    ChatTurnMetadata turnMetadata = const ChatTurnMetadata.empty(),
  }) async {
    // Device-only AI: the runtime authenticates
    // with the user's own LLM key, not this token. In local-only mode there is
    // no cloud session, so synthesize one scoped to [ownerUserId] — the API
    // client requires a non-null session but ignores its token on-device.
    final session =
        _sessionReader() ??
        AuthSession(
          accessToken: '',
          userId: ownerUserId,
          deviceId: 'local-device',
          expiresAt: DateTime.utc(2100),
        );
    await _ensureChatSessionExists(
      _store,
      sessionId: sessionId,
      ownerUserId: ownerUserId,
      model: model,
    );

    final history = await _store.listMessages(sessionId);

    final now = DateTime.now().toUtc();
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      sessionId: sessionId,
      ownerUserId: ownerUserId,
      role: ChatRole.user,
      content: content,
      status: ChatMessageStatus.complete,
      createdAt: now,
    );
    await _store.insertMessage(userMessage);
    await _autotitleChatSessionIfNeeded(_store, sessionId, content);

    final assistantId = _uuid.v4();
    var assistant = ChatMessage(
      id: assistantId,
      sessionId: sessionId,
      ownerUserId: ownerUserId,
      role: ChatRole.assistant,
      content: '',
      status: ChatMessageStatus.streaming,
      // Force the assistant placeholder strictly after the user turn so
      // the `ORDER BY created_at, id` sort never flips them when both
      // inserts land on the same wall millisecond — UUIDs sort
      // arbitrarily and on a fast machine the assistant id can land
      // ahead of the user id.
      createdAt: now.add(const Duration(milliseconds: 1)),
    );
    await _store.insertMessage(assistant);

    final ctx = buildContextWindow(history: history, pending: content);

    // Prepend route context without using a system role; the backend owns the
    // system prompt and accepts only user / assistant turns on this endpoint.
    final wireMessages = <WireMessage>[
      if (systemContext != null && systemContext.isNotEmpty)
        WireMessage(role: 'user', content: 'Context:\n$systemContext'),
      ...ctx.wire,
    ];
    if (ctx.droppedTurns > 0) {
      await insertSystemNotice(
        sessionId: sessionId,
        ownerUserId: ownerUserId,
        content: ChatRepository.contextTruncatedNotice(ctx.droppedTurns),
      );
    }
    final portfolioSnapshot = await _portfolioSnapshotReader?.call();

    // Build the typed ContextPack + seed an AiTrace keyed by the assistant
    // message id. Failures here are absorbed: chat must never break because
    // the AI transparency layer hiccupped, so the prep closure already
    // returns null on its own errors.
    final prepResult = _tracePrep == null
        ? null
        : await _tracePrep.call(requestId: assistantId, userMessage: content);
    final contextPack = prepResult?.pack;
    final traceSeed = prepResult?.traceSeed;
    final traceBuilder = traceSeed == null
        ? null
        : AiTraceBuilder.fromSeed(
            traceSeed,
            capturePayloads: prepResult?.traceVerbose ?? false,
          );
    if (traceBuilder != null && turnMetadata.invocationTrace != null) {
      traceBuilder.attachInvocation(turnMetadata.invocationTrace!);
    }
    traceBuilder?.addTurnAttributes(_contextPackTraceAttributes(contextPack));

    // Interleaved record of the assistant turn. `segments` and
    // `invocationOrder` together rebuild the original
    // text → tool → text → tool sequence the model emitted: each new
    // tool boundary closes the current trailing segment and opens a
    // fresh empty one. Invariant: `segments.length ==
    // invocationOrder.length + 1`.
    final segments = <String>[''];
    final reasoning = StringBuffer();
    final invocations = <String, ToolInvocation>{};
    final invocationOrder = <String>[];
    final localCancel = cancelToken ?? CancelToken();
    SendOutcome outcome = SendOutcome.completed;
    // Granular terminal reason for the finalised trace.
    // SendOutcome collapses error/cancel into the user-visible shape;
    // the trace surface needs the finer split so the audit page can
    // tell "user cancelled" from "stream errored" from "policy denied".
    TerminalReason terminalReason = TerminalReason.done;
    var sawStreamEvent = false;
    var sawDone = false;

    try {
      final stream = _api.chat(
        session: session,
        messages: wireMessages,
        turnId: assistantId,
        sessionId: sessionId,
        threadId: sessionId,
        surface: 'ai_chat',
        agentId: 'ai_chat',
        mode: 'chat',
        metadata: <String, Object?>{
          ...turnMetadata.toAgentMetadata(),
          'owner_user_id': ownerUserId,
          'assistant_message_id': assistantId,
        },
        portfolioSnapshot: portfolioSnapshot,
        contextPack: contextPack,
        model: model,
        cancelToken: localCancel,
      );

      await for (final event in stream) {
        sawStreamEvent = true;
        switch (event) {
          case TextEvent(:final text):
            segments[segments.length - 1] = segments.last + text;
            assistant = assistant.copyWith(
              content: segments.join(),
              textSegments: List<String>.unmodifiable(segments),
            );
            await _store.updateMessage(assistant);
          case ThinkingDeltaEvent(:final text):
            reasoning.write(text);
            assistant = assistant.copyWith(reasoningText: reasoning.toString());
            await _store.updateMessage(assistant);
          case ToolCallStartEvent(:final id, :final name):
            if (!invocationOrder.contains(id)) {
              invocationOrder.add(id);
              segments.add('');
            }
            invocations[id] = ToolInvocation(
              id: id,
              name: name,
              input: null,
              status: ToolInvocationStatus.streamingInput,
            );
            assistant = assistant.copyWith(
              toolCalls: [for (final k in invocationOrder) invocations[k]!],
              textSegments: List<String>.unmodifiable(segments),
            );
            await _store.updateMessage(assistant);
          case ToolCallDeltaEvent(:final id, :final partialInputJson):
            final existing = invocations[id];
            if (existing == null) {
              if (!invocationOrder.contains(id)) {
                invocationOrder.add(id);
                segments.add('');
              }
              invocations[id] = ToolInvocation(
                id: id,
                name: '',
                input: partialInputJson,
                status: ToolInvocationStatus.streamingInput,
                partialInputJson: partialInputJson,
              );
            } else {
              final nextPartialInputJson =
                  '${existing.partialInputJson ?? ''}$partialInputJson';
              invocations[id] = existing.copyWith(
                input: nextPartialInputJson,
                status: ToolInvocationStatus.streamingInput,
                partialInputJson: nextPartialInputJson,
              );
            }
            assistant = assistant.copyWith(
              toolCalls: [for (final k in invocationOrder) invocations[k]!],
              textSegments: List<String>.unmodifiable(segments),
            );
            await _store.updateMessage(assistant);
          case ToolCallEvent(:final id, :final name, :final input):
            // First sighting of this id → close the active text
            // segment and start a new trailing one.
            if (!invocationOrder.contains(id)) {
              invocationOrder.add(id);
              segments.add('');
            }
            final existing = invocations[id];
            invocations[id] = ToolInvocation(
              id: id,
              name: name.isEmpty ? (existing?.name ?? '') : name,
              input: input,
              output: existing?.output,
              status: ToolInvocationStatus.pendingResult,
              partialInputJson: existing?.partialInputJson,
            );
            assistant = assistant.copyWith(
              toolCalls: [for (final k in invocationOrder) invocations[k]!],
              textSegments: List<String>.unmodifiable(segments),
            );
            await _store.updateMessage(assistant);
          case ToolResultEvent(:final id, :final output):
            final existing = invocations[id];
            // A tool_result for an unseen id means the call was
            // synthesised server-side (e.g. proposal cap rejection).
            // Treat it like a fresh tool call so the segment list
            // still satisfies its length invariant.
            if (!invocationOrder.contains(id)) {
              invocationOrder.add(id);
              segments.add('');
            }
            invocations[id] = existing == null
                ? ToolInvocation(
                    id: id,
                    name: '',
                    input: null,
                    output: output,
                    status: ToolInvocationStatus.completed,
                  )
                : existing.copyWith(
                    output: output,
                    status: ToolInvocationStatus.completed,
                  );
            assistant = assistant.copyWith(
              toolCalls: [for (final k in invocationOrder) invocations[k]!],
              textSegments: List<String>.unmodifiable(segments),
              clearProgress: true,
            );
            await _store.updateMessage(assistant);
          case ErrorEvent(:final message):
            outcome = SendOutcome.errored;
            terminalReason = TerminalReason.streamError;
            assistant = assistant.copyWith(
              status: ChatMessageStatus.errored,
              errorMessage: message,
              clearProgress: true,
            );
            await _store.updateMessage(assistant);
          case UsageEvent(:final usage):
            assistant = assistant.copyWith(usage: usage);
            await _store.updateMessage(assistant);
          case ProgressEvent(:final progress):
            assistant = assistant.copyWith(progress: progress);
            await _store.updateMessage(assistant);
          case SpanEvent():
            // Observability-only: never mutates the assistant turn.
            // The builder anchors wall-clock times to the trace start
            // and strips payloads unless verbose capture is on.
            traceBuilder?.addSpan(
              id: event.id,
              parentId: event.parentId,
              kind: event.kind,
              name: event.name,
              startedAt: event.startedAt,
              endedAt: event.endedAt,
              status: event.status,
              errorCode: event.errorCode,
              errorMessage: event.errorMessage,
              tokens: event.tokens,
              model: event.model,
              stopReason: event.stopReason,
              input: event.input,
              output: event.output,
              attributes: event.attributes,
            );
          case DoneEvent(:final stopReason):
            sawDone = true;
            // Only flip to complete if no error frame already promoted
            // the message to errored. The stop reason is captured either
            // way so the UI can distinguish "natural end" from
            // "max_tokens / tool_use budget / refusal" without changing
            // the persistence model.
            final reason = ChatStopReasonX.parse(stopReason);
            if (reason == ChatStopReason.error &&
                assistant.status != ChatMessageStatus.errored) {
              outcome = SendOutcome.errored;
              terminalReason = TerminalReason.streamError;
            }
            if (assistant.status != ChatMessageStatus.errored) {
              assistant = assistant.copyWith(
                status: reason == ChatStopReason.error
                    ? ChatMessageStatus.errored
                    : ChatMessageStatus.complete,
                stopReason: reason,
                clearProgress: true,
              );
            } else {
              assistant = assistant.copyWith(
                stopReason: reason,
                clearProgress: true,
              );
            }
            await _store.updateMessage(assistant);
        }
      }
      if (!sawStreamEvent) {
        outcome = SendOutcome.errored;
        terminalReason = TerminalReason.closedEarly;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: 'AI response stream ended without any events',
          stopReason: ChatStopReason.error,
          clearProgress: true,
        );
        await _store.updateMessage(assistant);
      } else if (!sawDone && assistant.status == ChatMessageStatus.streaming) {
        outcome = SendOutcome.errored;
        terminalReason = TerminalReason.closedEarly;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: 'AI response stream ended before done',
          stopReason: ChatStopReason.error,
          clearProgress: true,
        );
        await _store.updateMessage(assistant);
      }
    } catch (e) {
      if (_isUserCancelled(localCancel)) {
        outcome = SendOutcome.cancelled;
        terminalReason = TerminalReason.userCancel;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: kCancelledError,
          stopReason: ChatStopReason.error,
          clearProgress: true,
        );
        await _store.updateMessage(assistant);
      } else {
        outcome = SendOutcome.errored;
        terminalReason = TerminalReason.streamError;
        assistant = assistant.copyWith(
          status: ChatMessageStatus.errored,
          errorMessage: _describeError(e),
          stopReason: ChatStopReason.error,
          clearProgress: true,
        );
        await _store.updateMessage(assistant);
      }
    } finally {
      await _store.touchSession(sessionId, DateTime.now().toUtc());
      // Append the trace last so a failure here can never sneak past
      // and skip session.touch — chat history takes priority over
      // transparency. The optional onTraceFinalized callback is retained
      // as a post-trace hook for diagnostics and tests.
      if (traceBuilder != null && _traceStore != null) {
        try {
          final trace = traceBuilder.finalize(
            finishedAt: DateTime.now().toUtc(),
            terminalReason: terminalReason,
          );
          await _traceStore.append(trace);
          _onTraceFinalized?.call(trace);
        } catch (_) {
          // Tracing is best-effort.
        }
      }
    }

    return outcome;
  }

  String _describeError(Object e) {
    if (e is AiChatRequestException) {
      return e.message;
    }
    return e.toString();
  }

  bool _isUserCancelled(CancelToken token) {
    return token.cancelError?.error == _userCancelledReason;
  }
}

Map<String, Object?> _contextPackTraceAttributes(ContextPack? pack) {
  if (pack == null) {
    return const <String, Object?>{
      'context_pack_present': false,
      'context_pack_json_bytes': 0,
      'context_appendix_present': false,
      'context_appendix_bytes': 0,
    };
  }
  final appendix = renderContextPackSystemAppendix(pack);
  return <String, Object?>{
    'context_pack_present': true,
    'context_pack_json_bytes': pack.serializedByteSize,
    'context_pack_budget_bytes': pack.budget.byteCap,
    'context_pack_budget_tier': pack.budget.tier.wire,
    'context_appendix_present': appendix != null,
    'context_appendix_bytes': appendix == null
        ? 0
        : utf8.encode(appendix).length,
    'context_appendix_cap_bytes': kUserProfileAppendixByteCap,
  };
}
