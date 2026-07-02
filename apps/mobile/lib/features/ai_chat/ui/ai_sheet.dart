/// The single entry point for AI as an overlay sheet.
///
/// Replaces the two historically separate surfaces — `showAiChatSheet`
/// (FAB / command palette) and `showAiBottomSheet` (object capsule) —
/// whose only real differences are *mode*, not architecture. One API,
/// one [AiSheetShell], two modes:
///
///  - **conversation** (`invocation == null`): resumes the user's
///    default thread via [defaultChatSessionProvider] and shows the
///    composer, optionally [prefill]ed. Mobile → 70 vh bottom sheet;
///    tablet / desktop → a 480×600 draggable floating card whose
///    position persists across opens.
///  - **invocation** (`invocation != null`): the object-semantic
///    surface (§5.4 "AI 进入用户当前页面"). Spins up a fresh thread
///    titled from the intent, fires the rendered prompt immediately,
///    offers reply chips + an "expand to chat" footer, and has no
///    composer. Bottom sheet at every width — it carries its own
///    context header, so it never free-floats.
///
/// Hard constraints (§5.8) carried over from the invocation surface:
///   - The only entry point for AI from outside the chat tab
///   - Reuses `ChatRepository.sendMessage` — no separate runtime path
///   - Attaches `AiIntentInvocation.toTraceJson()` to AiTrace
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/composition/ai_context.dart';

import '../../../core/ai/intent/intent.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/auth/current_user.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../domain/chat_turn_metadata.dart';
import '../state/chat_controller.dart';
import '../state/chat_session_scope.dart';
import 'ai_navigation.dart';
import 'chat_composer.dart';
import 'chat_conversation_view.dart';
import 'decision_request.dart';
import 'llm_profile_chip.dart';

part 'ai_sheet_views.dart';
part 'ai_sheet_overlay.dart';

/// Open the AI sheet. Pass [invocation] for the object-semantic mode;
/// otherwise it opens (or resumes) the user's conversation. Never
/// construct [AiSheetShell] directly and never push `/ai` for a
/// non-conversation entry point — call this.
Future<void> showAiSheet(
  BuildContext context, {
  AiIntentInvocation? invocation,
  String? objectLabel,
  String? prefill,
}) {
  if (invocation != null) {
    return showAppFormSheet<void>(
      context: context,
      maxHeightFactor: 0.95,
      builder: (_) => _SheetFrame(
        child: AiSheetShell.invocation(
          invocation: invocation,
          objectLabel: objectLabel,
        ),
      ),
    );
  }

  final width = MediaQuery.sizeOf(context).width;
  if (Breakpoints.isMobile(width)) {
    return showAppFormSheet<void>(
      context: context,
      maxHeightFactor: 0.95,
      builder: (_) =>
          _SheetFrame(child: AiSheetShell.conversation(prefill: prefill)),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'ai-chat-sheet',
    barrierDismissible: true,
    barrierColor: SemanticColors.of(context).scrim,
    transitionDuration: AiMotion.duration(context, Motion.medium),
    pageBuilder: (ctx, animation, secondaryAnimation) =>
        _DesktopSheetOverlay(prefill: prefill),
  );
}

/// The unified sheet content. `invocation == null` ⇒ conversation mode
/// (default thread + composer); otherwise invocation mode (fresh thread
/// + fired prompt + reply chips + footer). One widget so a new chat
/// affordance is added in exactly one place.
class AiSheetShell extends ConsumerStatefulWidget {
  const AiSheetShell.conversation({super.key, this.prefill})
    : invocation = null,
      objectLabel = null;

  const AiSheetShell.invocation({
    super.key,
    required AiIntentInvocation this.invocation,
    this.objectLabel,
  }) : prefill = null;

  /// Non-null ⇒ invocation mode.
  final AiIntentInvocation? invocation;

  /// Human label for the object ("Netflix 订阅", "投资账户") — fills
  /// `{{object_label}}` in the prompt template and the context header.
  final String? objectLabel;

  /// Conversation-mode composer pre-fill (command palette assistant entry).
  final String? prefill;

  bool get isInvocation => invocation != null;

  @override
  ConsumerState<AiSheetShell> createState() => _AiSheetShellState();
}

class _AiSheetShellState extends ConsumerState<AiSheetShell> {
  // Invocation-mode state only.
  String? _sessionId;
  bool _kicked = false;
  bool _loginRequired = false;
  String? _errorDetail;
  bool _overlaySettled = false;
  Timer? _overlaySettleTimer;

  // Conversation-mode: when the user taps "new conversation" we create a
  // fresh thread and pin it here, overriding the resumed default session
  // (`defaultChatSessionProvider`, which otherwise always reopens the last
  // thread). Null ⇒ use the resolved default.
  String? _convSessionId;
  bool _startingNew = false;

  Future<void> _startNewConversation(String ownerUserId) async {
    if (_startingNew) return;
    setState(() => _startingNew = true);
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final session = await repo.createSession(ownerUserId: ownerUserId);
      if (!mounted) return;
      setState(() => _convSessionId = session.id);
    } finally {
      if (mounted) setState(() => _startingNew = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _overlaySettleTimer = Timer(Motion.medium, () {
      if (!mounted) return;
      setState(() => _overlaySettled = true);
      if (widget.isInvocation) {
        unawaited(_kick());
      }
    });
  }

  @override
  void dispose() {
    _overlaySettleTimer?.cancel();
    super.dispose();
  }

  // ── Invocation mode ──────────────────────────────────────────────

  Future<void> _kick() async {
    if (_kicked) return;
    _kicked = true;
    final invocation = widget.invocation!;
    final ownerUserId = ref.read(activeUserIdProvider);
    if (ownerUserId == null) {
      setState(() => _loginRequired = true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final copyResolver = localizedIntentCopyResolver(l10n);
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      // Real session backed by ChatHistoryStore so "expand to chat" can
      // take over without rebuilding state. Title encodes the intent
      // for sidebar legibility.
      final intentCatalog = ref.read(intentCatalogProvider);
      final desc = intentCatalog.lookup(invocation.intent);
      final title = desc != null
          ? '${localizedIntentLabel(l10n, desc)} · ${widget.objectLabel ?? invocation.object?.type ?? "AI"}'
          : (widget.objectLabel ?? 'AI');
      final session = await repo.createSession(
        ownerUserId: ownerUserId,
        title: title,
      );
      if (!mounted) return;
      setState(() => _sessionId = session.id);
      final prompt = renderPromptFor(
        invocation,
        objectLabel: widget.objectLabel,
        defaultTimeframe: l10n.aiIntentDefaultTimeframe,
        copyResolver: copyResolver,
        catalog: intentCatalog,
        fallbackObjectLabel: l10n.aiIntentCurrentObject,
        fallbackPromptTemplate: l10n.aiIntentFallbackPrompt('{{object_label}}'),
      );
      unawaited(
        ref
            .read(chatControllerProvider(session.id).notifier)
            .send(
              prompt,
              turnMetadata: ChatTurnMetadata(
                invocationTrace: invocation.toTraceJson(),
              ),
            ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorDetail = '$e');
    }
  }

  void _sendChip(String sessionId, String chip) {
    ref
        .read(chatControllerProvider(sessionId).notifier)
        .send(
          chip,
          turnMetadata: ChatTurnMetadata(
            invocationTrace: widget.invocation?.toTraceJson(),
          ),
        );
  }

  void _chooseDecision(
    String sessionId,
    DecisionSelectionRequest selection, {
    String? systemContext,
  }) {
    final decision = DecisionSelection(
      optionId: selection.option.id,
      label: selection.option.label,
      reply: selection.reply,
      selectedAt: DateTime.now().toUtc(),
    );
    unawaited(
      ref
          .read(chatControllerProvider(sessionId).notifier)
          .chooseDecision(
            messageId: selection.messageId,
            toolInvocationId: selection.toolInvocationId,
            selection: decision,
            systemContext: systemContext,
            invocationTrace: widget.invocation?.toTraceJson(),
          ),
    );
  }

  void _expandToChat() {
    final sid = _sessionId;
    if (sid == null) return;
    popThenPushFromAiSurface(context, aiHistoryLocation(sid));
  }

  Widget _buildInvocation(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InvocationHeader(
            invocation: widget.invocation!,
            objectLabel: widget.objectLabel,
          ),
          const FDivider(),
          Expanded(child: _invocationBody()),
          if (_sessionId != null) ...[
            const FDivider(),
            _Footer(
              onExpand: _expandToChat,
              onDismiss: () => Navigator.of(context).maybePop(),
            ),
          ],
          if (_loginRequired || _errorDetail != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                AppSpacing.s12,
                AppSpacing.s16,
                AppSpacing.s16,
              ),
              child: Text(
                _loginRequired
                    ? l10n.aiChatLoginRequired
                    : l10n.commonLoadError(_errorDetail!),
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.destructive,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _invocationBody() {
    final sessionId = _sessionId;
    if (sessionId == null) {
      // The header already shows the invocation context, so the body
      // should feel "AI is about to talk", not "loading…".
      return _BodySkeleton(animated: _overlaySettled);
    }
    return ChatConversationView(
      sessionId: sessionId,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s16,
      ),
      invocationIntent: widget.invocation!.intent,
      onReplyChip: (chip) => _sendChip(sessionId, chip),
      onDecisionSelect: (selection) => _chooseDecision(sessionId, selection),
      loadingBuilder: (_) => const _BodySkeleton(),
      emptyBuilder: (_) => const _BodySkeleton(),
    );
  }

  // ── Conversation mode ────────────────────────────────────────────

  Widget _buildConversation(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Device-only AI works account-less; scope by the active user id
    // ([kLocalOnlyUserId] in local-only mode). `null` only before auth
    // settles, which the surrounding shell guards.
    final userId = ref.watch(activeUserIdProvider);

    if (userId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FLucideIcons.lock,
                size: AppIconSizes.xl,
                color: context.theme.colors.mutedForeground,
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(l10n.aiChatLoginRequired),
            ],
          ),
        ),
      );
    }

    if (!_overlaySettled) {
      return Column(
        children: [
          _ConversationHeader(title: l10n.aiChatSheetTitle),
          const FDivider(),
          const Expanded(child: _BodySkeleton(animated: false)),
        ],
      );
    }

    final resolvedDefault = ref
        .watch(defaultChatSessionProvider(userId))
        .asData
        ?.value;
    // A user-started fresh thread wins over the resumed default.
    final activeId = _convSessionId ?? resolvedDefault;

    return Column(
      children: [
        _ConversationHeader(
          title: l10n.aiChatSheetTitle,
          onNew: activeId == null || _startingNew
              ? null
              : () => _startNewConversation(userId),
          onExpand: activeId == null
              ? null
              : () => popThenPushFromAiSurface(
                  context,
                  aiHistoryLocation(activeId),
                ),
        ),
        const FDivider(),
        Expanded(
          child: activeId == null
              ? const Center(child: FCircularProgress())
              : ChatConversationView(
                  sessionId: activeId,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  // Only surface a tappable choice list when the model
                  // actually wrote a menu — no generic canned reply chips
                  // trailing every plain turn.
                  suggestCannedReplies: false,
                  // A tap sends the chosen option as the next user message.
                  onReplyChip: (chip) {
                    final routeCtx = ref.read(aiContextProvider);
                    ref
                        .read(chatControllerProvider(activeId).notifier)
                        .send(chip, systemContext: routeCtx.toSystemContext());
                  },
                  onDecisionSelect: (selection) {
                    final routeCtx = ref.read(aiContextProvider);
                    _chooseDecision(
                      activeId,
                      selection,
                      systemContext: routeCtx.toSystemContext(),
                    );
                  },
                  emptyBuilder: (context) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s24),
                      child: Text(
                        AppLocalizations.of(context).aiChatSheetEmpty,
                        style: context.bodyCaptionStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
        ),
        if (activeId != null) ...[
          const LlmProfileChip(),
          _ConversationComposer(sessionId: activeId, prefill: widget.prefill),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.isInvocation
        ? _buildInvocation(context)
        : _buildConversation(context);
  }
}
