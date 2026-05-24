/// Wave 35 / 36 — `PersistentUndoBanner`: global "已修改 X · 撤销" surface.
///
/// Sits above the bottom navigation bar in `AppShell`. Watches
/// `undoEntriesStreamProvider`; shows the newest non-expired entry
/// when present, hides otherwise. Tap "撤销" calls
/// `DriftUndoStack.take(token)` and dismisses the banner.
///
/// Wave 36 refactor — uses `AiSparkle` / `AiType` / `AiMotion` from
/// `core/ai/visual/` so the banner shares the visual language of
/// every other AI surface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../visual/visual.dart';
import 'drift_undo_stack.dart';
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
      if (e.expiresAt == null || e.expiresAt!.isAfter(now)) {
        top = e;
        break;
      }
    }
    return AnimatedSwitcher(
      duration: AiMotion.medium,
      switchInCurve: AiMotion.standard,
      switchOutCurve: AiMotion.standard,
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
    final stack = ref.read(undoStackProvider);
    if (stack == null) return;
    await stack.take(token);
    // The reverter (kind → impl) lookup is the caller's responsibility
    // — Wave 24 deliberately doesn't bake one in. The banner just
    // surfaces + removes; future Wave wires the reverter dispatch.
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
    return Material(
      color: AiTone.surfaceTint(context),
      elevation: 0,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const AiSparkle(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  style: AiType.body(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
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
