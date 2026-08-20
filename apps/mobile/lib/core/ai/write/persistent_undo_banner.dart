/// `PersistentUndoBanner`: global "已修改 X · 撤销" surface.
///
/// Sits above the bottom navigation bar in `AppShell`. Watches
/// `undoEntriesStreamProvider`; shows the newest non-expired entry
/// when present, hides otherwise. Tap "撤销" calls
/// `DriftUndoStack.take(token)` and dismisses the banner.
///
/// Uses `AiSparkle` / `AiType` from
/// `core/ai/visual/` so the banner shares the visual language of
/// every other AI surface.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../visual/visual.dart';
import 'drift_undo_stack.dart';
import 'persisted_undo_dispatcher.dart';
import 'providers.dart';

class PersistentUndoBanner extends ConsumerWidget {
  const PersistentUndoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(undoEntriesStreamProvider);
    final entries = entriesAsync.value ?? const <PersistedUndoEntry>[];
    // Pick the newest *unexpired* entry. Expired entries linger in the
    // stack until pruned, so we filter here too.
    final now = DateTime.now().toUtc();
    PersistedUndoEntry? top;
    for (final e in entries) {
      if (!e.showGlobalBanner) continue;
      if (e.expiresAt == null || e.expiresAt!.isAfter(now)) {
        top = e;
        break;
      }
    }
    return AnimatedSwitcher(
      duration: AppMotionPolicy.duration(context, Motion.medium),
      switchInCurve: Motion.aiCalm,
      switchOutCurve: Motion.aiCalm,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: top == null
          ? const SizedBox.shrink(key: ValueKey('_empty'))
          : _UndoRow(
              key: ValueKey(top.token),
              entry: top,
              onUndo: () => _handleUndo(ref, top!.token),
            ),
    );
  }

  Future<void> _handleUndo(WidgetRef ref, String token) async {
    final dispatcher = ref.read(persistedUndoDispatcherProvider);
    if (dispatcher == null) return;
    await dispatcher.undo(token);
  }
}

class _UndoRow extends StatelessWidget {
  const _UndoRow({super.key, required this.entry, required this.onUndo});

  final PersistedUndoEntry entry;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final summary =
        entry.payload['summary_zh'] as String? ??
        entry.payload['summaryZh'] as String? ??
        entry.kind;
    return ColoredBox(
      color: AiTone.surfaceTint(context),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s10,
          ),
          child: Row(
            children: [
              const AiSparkle(),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: summary,
                  excludeSemantics: true,
                  child: Text(
                    summary,
                    style: AiType.body(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AiPill(
                label: AppLocalizations.of(context).commonUndo,
                state: AiPillState.selected,
                onTap: onUndo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
