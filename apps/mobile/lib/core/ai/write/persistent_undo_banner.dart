/// Wave 35 — `PersistentUndoBanner`: global "已修改 X · 撤销" surface.
///
/// Sits above the bottom navigation bar in `AppShell`. Watches
/// `undoEntriesStreamProvider`; shows the newest non-expired entry
/// when present, hides otherwise. Tap "撤销" calls
/// `DriftUndoStack.take(token)` and dismisses the banner.
///
/// Calm Intelligence (§5.6): surface tone background, single
/// `auto_awesome_outlined` 14px sparkle, no glow, no slide-in
/// animation beyond a 200ms opacity fade.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
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
    final scheme = Theme.of(context).colorScheme;
    final summary = entry.payload['summary_zh'] as String? ??
        entry.payload['summaryZh'] as String? ??
        entry.kind;
    return Material(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onUndo,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('撤销'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
