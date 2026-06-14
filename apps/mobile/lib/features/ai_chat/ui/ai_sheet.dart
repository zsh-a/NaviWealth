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
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/intent/intent.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/auth/current_user.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../state/ai_context.dart';
import '../state/chat_controller.dart';
import '../state/chat_session_scope.dart';
import 'chat_composer.dart';
import 'chat_conversation_view.dart';
import 'llm_profile_chip.dart';

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

/// Bottom-sheet frame that stays usable while the soft keyboard is up.
///
/// `showFSheet` slides a fixed-height box up from the bottom. This
/// route opts out of forui's automatic inset shifting so keyboard
/// avoidance has a single owner here: without compensation the composer
/// / footer buttons sit behind the keyboard and can't be tapped. This frame:
///
///  - reads `viewInsets` *inside* the subtree so it rebuilds when the
///    keyboard toggles,
///  - grows the sheet toward full height while the keyboard is open so
///    the conversation keeps usable room, and
///  - pads the body up by the keyboard height so the composer/footer
///    rest just above it.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final screenH = mq.size.height;
    // Short viewports open full-height (matches the old invocation
    // rule); otherwise 70 vh, expanding by the keyboard height (capped
    // near full screen) so the visible area doesn't collapse.
    final base = screenH < 500 ? screenH : screenH * 0.7;
    final height = keyboard > 0
        ? math.min(screenH * 0.95, base + keyboard)
        : base;
    return SizedBox(
      height: height,
      child: AnimatedPadding(
        duration: AiMotion.duration(context, Motion.fast),
        curve: AiMotion.standard,
        padding: EdgeInsets.only(bottom: keyboard),
        child: child,
      ),
    );
  }
}

/// Desktop conversation overlay: a 480 × 600 draggable floating card.
/// Position defaults to bottom-right and persists to SharedPreferences.
class _DesktopSheetOverlay extends ConsumerStatefulWidget {
  const _DesktopSheetOverlay({this.prefill});

  final String? prefill;

  @override
  ConsumerState<_DesktopSheetOverlay> createState() =>
      _DesktopSheetOverlayState();
}

class _DesktopSheetOverlayState extends ConsumerState<_DesktopSheetOverlay> {
  static const _prefKey = 'naviwealth.ai_chat.sheet_offset';

  // Default + bounds for the resizable sheet. The min keeps the
  // composer + at least one bubble visible; the max stops the user
  // from dragging it beyond a usable second-window size.
  static const Size _defaultSize = Size(480, 600);
  static const Size _minSize = Size(360, 420);
  static const Size _maxSize = Size(880, 960);

  Offset? _offset;
  Size? _size;

  @override
  void initState() {
    super.initState();
    _loadPersisted();
  }

  Future<void> _loadPersisted() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final dx = prefs.getDouble('$_prefKey.dx');
    final dy = prefs.getDouble('$_prefKey.dy');
    final w = prefs.getDouble('$_prefKey.w');
    final h = prefs.getDouble('$_prefKey.h');
    if (!mounted) return;
    setState(() {
      if (dx != null && dy != null) _offset = Offset(dx, dy);
      if (w != null && h != null) _size = Size(w, h);
    });
  }

  Future<void> _persistPosition(Offset o) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setDouble('$_prefKey.dx', o.dx),
      prefs.setDouble('$_prefKey.dy', o.dy),
    ]);
  }

  Future<void> _persistSize(Size s) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setDouble('$_prefKey.w', s.width),
      prefs.setDouble('$_prefKey.h', s.height),
    ]);
  }

  Size _effectiveSize() {
    final s = _size ?? _defaultSize;
    return Size(
      s.width.clamp(_minSize.width, _maxSize.width),
      s.height.clamp(_minSize.height, _maxSize.height),
    );
  }

  Offset _defaultPosition(Size screenSize, Size sheetSize) {
    return Offset(
      screenSize.width - sheetSize.width - 24,
      screenSize.height - sheetSize.height - 24,
    );
  }

  Offset _clampToScreen(Offset o, Size screenSize, Size sheetSize) {
    final maxDx = (screenSize.width - sheetSize.width).clamp(
      0.0,
      double.infinity,
    );
    final maxDy = (screenSize.height - sheetSize.height).clamp(
      0.0,
      double.infinity,
    );
    return Offset(o.dx.clamp(0.0, maxDx), o.dy.clamp(0.0, maxDy));
  }

  void _onHeaderDrag(DragUpdateDetails details, Size screenSize) {
    final sheetSize = _effectiveSize();
    final base = _offset ?? _defaultPosition(screenSize, sheetSize);
    setState(() {
      _offset = _clampToScreen(
        Offset(base.dx + details.delta.dx, base.dy + details.delta.dy),
        screenSize,
        sheetSize,
      );
    });
  }

  void _onHeaderDragEnd() {
    final o = _offset;
    if (o != null) _persistPosition(o);
  }

  void _onResize(DragUpdateDetails details) {
    final cur = _effectiveSize();
    setState(() {
      _size = Size(
        (cur.width + details.delta.dx).clamp(_minSize.width, _maxSize.width),
        (cur.height + details.delta.dy).clamp(_minSize.height, _maxSize.height),
      );
    });
  }

  void _onResizeEnd(Size screenSize) {
    final s = _effectiveSize();
    _persistSize(s);
    // Resize-bigger may push the existing top-left position past the
    // screen edge — re-clamp + persist so the next open lands cleanly.
    final o = _offset;
    if (o != null) {
      final clamped = _clampToScreen(o, screenSize, s);
      if (clamped != o) {
        setState(() => _offset = clamped);
        _persistPosition(clamped);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final sheetSize = _effectiveSize();
    final basePos = _offset ?? _defaultPosition(screenSize, sheetSize);
    final pos = _clampToScreen(basePos, screenSize, sheetSize);
    // If the window shrank since last session and the persisted offset
    // now sits offscreen, write back the clamped offset so we don't
    // re-clamp on every build.
    if (_offset != null && pos != _offset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _offset = pos);
        _persistPosition(pos);
      });
    }

    final colors = context.theme.colors;
    return Stack(
      children: [
        Positioned(
          left: pos.dx,
          top: pos.dy,
          width: sheetSize.width,
          height: sheetSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: colors.border, width: 1),
                boxShadow: AppShadow.desktopSheet,
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Full-width draggable header strip — anywhere on
                      // the top 24px counts as a drag handle, not just
                      // the 36×4 pill (which was a visible-but-tiny
                      // hitbox most users never tried to grab).
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (d) => _onHeaderDrag(d, screenSize),
                        onPanEnd: (_) => _onHeaderDragEnd(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: SizedBox(
                            height: 24,
                            child: AppSheetDragHandle(colors: colors),
                          ),
                        ),
                      ),
                      Expanded(
                        child: AiSheetShell.conversation(
                          prefill: widget.prefill,
                        ),
                      ),
                    ],
                  ),
                  // SE-corner resize affordance — three short diagonal
                  // strokes, hit area extends a bit past the visual.
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: _onResize,
                      onPanEnd: (_) => _onResizeEnd(screenSize),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CustomPaint(
                            painter: _ResizeGripPainter(
                              color: colors.mutedForeground.withValues(
                                alpha: AppOpacity.scrim,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints three short diagonal strokes in the bottom-right corner so
/// the user can see where to grab to resize. Kept ultra-minimal —
/// macOS-style two-line "ear" or Windows-style three-dot grip.
class _ResizeGripPainter extends CustomPainter {
  _ResizeGripPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w - 14, h - 4), Offset(w - 4, h - 14), paint);
    canvas.drawLine(Offset(w - 10, h - 4), Offset(w - 4, h - 10), paint);
    canvas.drawLine(Offset(w - 6, h - 4), Offset(w - 4, h - 6), paint);
  }

  @override
  bool shouldRepaint(_ResizeGripPainter old) => old.color != color;
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

  /// Conversation-mode composer pre-fill (command palette "Ask AI").
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
        repo.sendMessage(
          sessionId: session.id,
          ownerUserId: ownerUserId,
          content: prompt,
          invocationTrace: invocation.toTraceJson(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorDetail = '$e');
    }
  }

  Future<void> _sendChip(String sessionId, String chip) async {
    final ownerUserId = ref.read(activeUserIdProvider);
    if (ownerUserId == null) return;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      unawaited(
        repo.sendMessage(
          sessionId: sessionId,
          ownerUserId: ownerUserId,
          content: chip,
          // Same invocation tag — trace attribution carries through
          // follow-up chip taps so the transparency page can group them.
          invocationTrace: widget.invocation!.toTraceJson(),
        ),
      );
    } catch (_) {
      // Best-effort: chip taps are non-critical.
    }
  }

  void _expandToChat() {
    final sid = _sessionId;
    if (sid == null) return;
    Navigator.of(context).pop();
    context.go('${AppRoutes.settingsAiHistory}?selected=$sid');
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
                style: context.theme.typography.sm.copyWith(
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
              : () {
                  Navigator.of(context).pop();
                  context.go(AppRoutes.settingsAiHistory);
                },
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
                  emptyBuilder: (context) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s24),
                      child: Text(
                        AppLocalizations.of(context).aiChatSheetEmpty,
                        style: context.theme.typography.sm.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
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

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.title, this.onExpand, this.onNew});
  final String title;
  final VoidCallback? onExpand;

  /// Start a fresh conversation (clears the resumed thread from view).
  /// Null while no session is resolved or a new one is being created.
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: [
          const AiSparkle(size: AppIconSizes.sm),
          const SizedBox(width: AppSpacing.s8),
          Expanded(child: Text(title, style: AiType.title(context))),
          FTooltip(
            tipBuilder: (_, _) => Text(l10n.aiChatSheetNewTooltip),
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: onNew,
              child: const Icon(FLucideIcons.squarePen, size: AppIconSizes.md),
            ),
          ),
          FTooltip(
            tipBuilder: (_, _) => Text(l10n.aiChatSheetExpandTooltip),
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: onExpand,
              child: const Icon(FLucideIcons.maximize, size: AppIconSizes.md),
            ),
          ),
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: () => Navigator.of(context).pop(),
            child: const Icon(FLucideIcons.x, size: AppIconSizes.md),
          ),
        ],
      ),
    );
  }
}

class _ConversationComposer extends ConsumerWidget {
  const _ConversationComposer({required this.sessionId, this.prefill});
  final String sessionId;
  final String? prefill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = ref.watch(chatControllerProvider(sessionId));
    final routeCtx = ref.watch(aiContextProvider);
    return ChatComposer(
      isStreaming: turn.isStreaming,
      initialText: prefill,
      onSend: (text) {
        ref
            .read(chatControllerProvider(sessionId).notifier)
            .send(text, systemContext: routeCtx.toSystemContext());
      },
      onCancel: () {
        ref.read(chatControllerProvider(sessionId).notifier).cancel();
      },
    );
  }
}

class _InvocationHeader extends ConsumerWidget {
  const _InvocationHeader({required this.invocation, this.objectLabel});
  final AiIntentInvocation invocation;
  final String? objectLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desc = ref.watch(intentCatalogProvider).lookup(invocation.intent);
    final l10n = AppLocalizations.of(context);
    // Single inline header row: sparkle + intent label + middot +
    // object label, so context stays visible while the body scrolls.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s4,
        AppSpacing.s20,
        AppSpacing.s12,
      ),
      child: Row(
        children: [
          const AiSparkle(),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: localizedIntentLabel(l10n, desc),
                    style: AiType.label(context),
                  ),
                  if (objectLabel != null) ...[
                    TextSpan(text: '  ·  ', style: AiType.meta(context)),
                    TextSpan(text: objectLabel!, style: AiType.meta(context)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shape that materialises into the first assistant turn —
/// three muted bars sized like a chat bubble, pulsing subtly.
class _BodySkeleton extends StatefulWidget {
  const _BodySkeleton({this.animated = true});

  final bool animated;

  @override
  State<_BodySkeleton> createState() => _BodySkeletonState();
}

class _BodySkeletonState extends State<_BodySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  bool _configured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _ctrl.duration = AiMotion.duration(context, Motion.shimmerCycle);
    if (widget.animated && !reduceMotion) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(_BodySkeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated == oldWidget.animated) return;
    if (widget.animated) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = widget.animated ? _ctrl.value : 0.0;
          // Lerp between 0.35 and 0.65 alpha — barely perceptible.
          final alpha = 0.35 + 0.30 * t;
          final color = AiTone.surfaceTint(context).withValues(alpha: alpha);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(color, widthFactor: 0.85),
              const SizedBox(height: AppSpacing.s8),
              _bar(color, widthFactor: 0.65),
              const SizedBox(height: AppSpacing.s8),
              _bar(color, widthFactor: 0.45),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(Color color, {required double widthFactor}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onExpand, required this.onDismiss});
  final VoidCallback onExpand;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s8,
        AppSpacing.s12,
        AppSpacing.s8,
      ),
      child: Row(
        children: [
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onDismiss,
            prefix: const Icon(FLucideIcons.x, size: AppIconSizes.sm),
            child: Text(l10n.commonClose),
          ),
          const Spacer(),
          FButton(
            variant: FButtonVariant.outline,
            onPress: onExpand,
            prefix: const Icon(FLucideIcons.maximize, size: AppIconSizes.sm),
            child: Text(l10n.aiChatSheetExpandTooltip),
          ),
        ],
      ),
    );
  }
}
