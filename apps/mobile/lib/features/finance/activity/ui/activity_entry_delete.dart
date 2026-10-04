import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/current_user.dart';
import '../../../../core/forms/form_undo.dart';
import '../../../../core/logging/providers.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../data/activity_feed_provider.dart';

/// Called only after the list or detail surface has confirmed deletion.
/// Captures the shared scope so Undo remains usable after the row/page leaves.
Future<bool> deleteActivityEntryWithUndo(
  BuildContext context,
  String entryId, {
  VoidCallback? onDeleted,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final owner = container.read(activeUserIdProvider);
  final l10n = AppLocalizations.of(context);
  final logger = container.read(loggerProvider);
  final feedbackContext = Navigator.of(context).context;
  AppMessenger.cacheOverlay(feedbackContext);
  try {
    final repository = await container.read(
      journalEntryRepositoryProvider.future,
    );
    if (container.read(activeUserIdProvider) != owner) return false;
    await repository.softDelete(entryId);
    if (container.read(activeUserIdProvider) != owner) return true;
    container.invalidate(activityFeedProvider);
    final offer = FormUndoOffer(
      message: l10n.activityEntryDeleted,
      action: FormUndoAction(() async {
        if (container.read(activeUserIdProvider) != owner) {
          throw StateError('Undo owner changed');
        }
        await repository.restoreSoftDeleted(entryId);
        container.invalidate(activityFeedProvider);
      }),
      actionLabel: l10n.commonUndo,
      successMessage: l10n.commonUndoSucceeded,
      failureMessage: (_) => l10n.commonUndoFailed,
      retryLabel: l10n.commonRetry,
      tag: 'activity-delete',
    );
    final offers = container.read(formUndoOfferProvider.notifier);
    offers.offer(offer);
    if (context.mounted) onDeleted?.call();
    if (feedbackContext.mounted) {
      AppMessenger.show(
        feedbackContext,
        ToastKind.success,
        l10n.activityEntryDeleted,
        actionLabel: l10n.commonUndo,
        onAction: () => unawaited(offers.run(feedbackContext, offer, logger)),
      );
    }
    return true;
  } catch (_) {
    if (feedbackContext.mounted) {
      AppMessenger.show(
        feedbackContext,
        ToastKind.error,
        l10n.activityEntryDeleteFailed,
      );
    }
    return false;
  }
}
