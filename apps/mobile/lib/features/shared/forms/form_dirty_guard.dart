import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

// The pure dirty-tracking primitive lives in the design-system layer so
// `showAppFormSheet` can consume it without a layering inversion. Re-
// exported here so feature forms keep importing it via the forms barrel.
export '../../../design_system/widgets/form_dirty_controller.dart';

/// Returns `true` when it is safe to leave the form: either nothing is
/// dirty, or the user confirmed discarding their edits. Reuses the
/// shared [showConfirmDialog] so the prompt matches every other
/// destructive confirm in the app.
Future<bool> confirmDiscardIfDirty(
  BuildContext context,
  FormDirtyController controller,
) async {
  if (!controller.isDirty) return true;
  final l10n = AppLocalizations.of(context);
  final discard = await showConfirmDialog(
    context: context,
    title: Text(l10n.unsavedChangesTitle),
    body: Text(l10n.unsavedChangesBody),
    cancelLabel: l10n.unsavedChangesKeepEditing,
    confirmLabel: l10n.unsavedChangesDiscard,
    destructive: true,
  );
  return discard == true;
}

/// Opens a guarded form sheet: creates a [FormDirtyController], wires it
/// into `showAppFormSheet` (which disables barrier-tap / swipe-down and
/// routes system back + footer Cancel through [confirmDiscardIfDirty]),
/// and disposes the controller when the sheet closes.
///
/// The sheet body receives the controller — bind its
/// [TextEditingController]s with [FormDirtyController.bindTextControllers],
/// call [FormDirtyController.markDirty] from non-text pickers, set
/// [FormDirtyController.busy] around submit and
/// [FormDirtyController.markPristine] right before the success pop.
Future<T?> showGuardedFormSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext sheetContext, FormDirtyController dirty)
  builder,
  double maxHeightFactor = 0.94,
}) async {
  final dirty = FormDirtyController();
  try {
    return await showAppFormSheet<T>(
      context: context,
      maxHeightFactor: maxHeightFactor,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (sheetContext) => builder(sheetContext, dirty),
    );
  } finally {
    dirty.dispose();
  }
}

/// Unsaved-changes protection for full-page forms.
///
/// Mix into the form's `ConsumerState`, expose [leaveFallback], wrap the
/// scaffold with [guardedScope], bind controllers via [dirty], and pass
/// [handleBackIntent] to `backHeaderAction(context, confirmLeave: …)`.
/// System / predictive back and the toolbar back arrow then funnel
/// through one [confirmDiscardIfDirty].
///
/// The programmatic post-save leave is a *direct* pop (`popOrGo` →
/// `GoRouter.pop`/`Navigator.pop`), which reports `didPop: true` and is
/// never prompted; only user-initiated back (which respects
/// [PopScope.canPop]) is guarded.
mixin FormDirtyGuard<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  final FormDirtyController dirty = FormDirtyController();

  /// Where to land when the form was deep-linked with no back stack.
  String get leaveFallback;

  /// Wrap the form's scaffold so user-initiated back is guarded.
  Widget guardedScope({required Widget child}) {
    return AnimatedBuilder(
      animation: dirty,
      builder: (context, _) {
        return PopScope(
          canPop: !dirty.isDirty && !dirty.busy,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || dirty.busy) return;
            final shouldLeave = await confirmDiscardIfDirty(context, dirty);
            if (!shouldLeave || !context.mounted) return;
            dirty.markPristine();
            popOrGo(context, fallback: leaveFallback);
          },
          child: child,
        );
      },
    );
  }

  /// Pass as `backHeaderAction(context, confirmLeave: handleBackIntent)`.
  Future<bool> handleBackIntent() => confirmDiscardIfDirty(context, dirty);

  @mustCallSuper
  @override
  void dispose() {
    dirty.dispose();
    super.dispose();
  }
}
