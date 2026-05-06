import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/auth/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../state/chat_controller.dart';
import '../state/route_context_provider.dart';
import 'chat_composer.dart';
import 'message_bubble.dart';

/// Shows the AI chat as a half-screen overlay.
///
/// On mobile (< 600 dp) this is a 70-vh glass modal bottom sheet.
/// On tablet / desktop it is a 480 × 600 floating card anchored to
/// the bottom-right corner of the screen.
///
/// When [prefill] is non-null, the chat composer is pre-filled with that text.
Future<void> showAiChatSheet(BuildContext context, {String? prefill}) {
  final width = MediaQuery.sizeOf(context).width;
  if (Breakpoints.isMobile(width)) {
    return _showMobileSheet(context, prefill: prefill);
  }
  return _showDesktopSheet(context, prefill: prefill);
}

Future<void> _showMobileSheet(BuildContext context, {String? prefill}) {
  return showGlassModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SheetSized(child: AiChatSheetBody(prefill: prefill)),
  );
}

Future<void> _showDesktopSheet(BuildContext context, {String? prefill}) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'ai-chat-sheet',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: Motion.medium,
    pageBuilder: (ctx, animation, secondaryAnimation) =>
        _DesktopSheetOverlay(prefill: prefill),
  );
}

/// Wraps the sheet body to 70 vh on mobile.
class _SheetSized extends StatelessWidget {
  const _SheetSized({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SizedBox(height: height, child: child);
  }
}

/// Desktop overlay: a 480 × 600 draggable floating card.
///
/// Position defaults to bottom-right and is persisted to
/// SharedPreferences so the sheet re-opens where the user left it.
class _DesktopSheetOverlay extends ConsumerStatefulWidget {
  const _DesktopSheetOverlay({this.prefill});

  final String? prefill;

  @override
  ConsumerState<_DesktopSheetOverlay> createState() =>
      _DesktopSheetOverlayState();
}

class _DesktopSheetOverlayState extends ConsumerState<_DesktopSheetOverlay> {
  static const _prefKey = 'naviwealth.ai_chat.sheet_offset';
  static const _sheetW = 480.0;
  static const _sheetH = 600.0;

  Offset? _offset;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final dx = prefs.getDouble('$_prefKey.dx');
    final dy = prefs.getDouble('$_prefKey.dy');
    if (dx != null && dy != null && mounted) {
      setState(() => _offset = Offset(dx, dy));
    }
  }

  Future<void> _persistPosition(Offset o) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setDouble('$_prefKey.dx', o.dx),
      prefs.setDouble('$_prefKey.dy', o.dy),
    ]);
  }

  Offset _defaultPosition(Size screenSize) {
    return Offset(
      screenSize.width - _sheetW - Spacing.s24,
      screenSize.height - _sheetH - Spacing.s24,
    );
  }

  Offset _clampToScreen(Offset o, Size screenSize) {
    final maxDx = screenSize.width - _sheetW;
    final maxDy = screenSize.height - _sheetH;
    return Offset(o.dx.clamp(0.0, maxDx), o.dy.clamp(0.0, maxDy));
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final pos = _clampToScreen(
      _offset ?? _defaultPosition(screenSize),
      screenSize,
    );

    return Stack(
      children: [
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: Material(
            color: Colors.transparent,
            elevation: 8,
            borderRadius: Radii.brXl,
            child: ClipRRect(
              borderRadius: Radii.brXl,
              child: GlassSurface(
                sigma: 20,
                borderRadius: Radii.brXl,
                border: Border.all(
                  color: GlassTokens.of(context).hairlineColor,
                  width: 1,
                ),
                child: SizedBox(
                  width: _sheetW,
                  height: _sheetH,
                  child: Column(
                    children: [
                      // Drag handle — only this area initiates drag.
                      GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _offset = Offset(
                              pos.dx + details.delta.dx,
                              pos.dy + details.delta.dy,
                            );
                          });
                        },
                        onPanEnd: (_) {
                          if (_offset != null) _persistPosition(_offset!);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: Spacing.s8),
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: AiChatSheetBody(prefill: widget.prefill)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The actual chat sheet content — shared between mobile and desktop
/// variants.
class AiChatSheetBody extends ConsumerStatefulWidget {
  const AiChatSheetBody({super.key, this.prefill});

  /// Optional text to pre-fill the chat composer with.
  final String? prefill;

  @override
  ConsumerState<AiChatSheetBody> createState() => _AiChatSheetBodyState();
}

class _AiChatSheetBodyState extends ConsumerState<AiChatSheetBody> {
  String? _sessionId;
  bool _bootstrapped = false;

  Future<void> _ensureSession(String ownerUserId) async {
    if (_sessionId != null) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    final existing = await ref.read(
      chatSessionsStreamProvider(ownerUserId).future,
    );
    if (!mounted) return;
    if (existing.isNotEmpty) {
      setState(() {
        _sessionId = existing.first.id;
        _bootstrapped = true;
      });
      return;
    }
    final session = await repo.createSession(ownerUserId: ownerUserId);
    if (!mounted) return;
    setState(() {
      _sessionId = session.id;
      _bootstrapped = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final session = ref.watch(authSessionReaderProvider)();

    if (session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 32, color: cs.onSurfaceVariant),
              const SizedBox(height: Spacing.s12),
              Text(l10n.aiChatLoginRequired),
            ],
          ),
        ),
      );
    }

    if (!_bootstrapped) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureSession(session.userId);
      });
    }

    final activeId = _sessionId;

    return Column(
      children: [
        // ── Header ──
        _SheetHeader(
          title: l10n.aiChatSheetTitle,
          onExpand: activeId == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  context.go(AppRoutes.ai);
                },
        ),
        const Divider(height: 1),
        // ── Messages ──
        Expanded(
          child: activeId == null
              ? const Center(child: CircularProgressIndicator())
              : _SheetMessages(sessionId: activeId),
        ),
        // ── Composer ──
        if (activeId != null)
          _SheetComposer(sessionId: activeId, prefill: widget.prefill),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.onExpand});
  final String title;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s12,
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 20, color: cs.primary),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_full, size: 20),
            tooltip: AppLocalizations.of(context).aiChatSheetExpandTooltip,
            onPressed: onExpand,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _SheetMessages extends ConsumerStatefulWidget {
  const _SheetMessages({required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<_SheetMessages> createState() => _SheetMessagesState();
}

class _SheetMessagesState extends ConsumerState<_SheetMessages> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Motion.fast,
        curve: Motion.standardDecelerate,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      chatMessagesStreamProvider(widget.sessionId),
    );
    ref.listen(chatMessagesStreamProvider(widget.sessionId), (_, next) {
      next.whenData((_) => _scrollToBottom());
    });

    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(AppLocalizations.of(context).commonLoadError(e.toString())),
      ),
      data: (messages) {
        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.s24),
              child: Text(
                AppLocalizations.of(context).aiChatSheetEmpty,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.s12,
            vertical: Spacing.s8,
          ),
          itemCount: messages.length,
          itemBuilder: (_, i) =>
              MessageBubble(sessionId: widget.sessionId, message: messages[i]),
        );
      },
    );
  }
}

class _SheetComposer extends ConsumerWidget {
  const _SheetComposer({required this.sessionId, this.prefill});
  final String sessionId;
  final String? prefill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final turn = ref.watch(chatControllerProvider(sessionId));
    final routeCtx = ref.watch(aiRouteContextProvider);
    return ChatComposer(
      isStreaming: turn.isStreaming,
      isFlushing: turn.isFlushing,
      initialText: prefill,
      onSend: (text) {
        ref
            .read(chatControllerProvider(sessionId).notifier)
            .send(
              text,
              staleSyncNotice: l10n.aiChatStaleSyncNotice,
              systemContext: routeCtx.toSystemContext(),
            );
      },
      onCancel: () {
        ref.read(chatControllerProvider(sessionId).notifier).cancel();
      },
    );
  }
}
