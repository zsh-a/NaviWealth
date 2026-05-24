import 'dart:async';

import 'package:flutter/material.dart' show Icons, Navigator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/providers.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../activity/ui/activity_entry_detail_page.dart';
import '../domain/dividend_center.dart';

/// Per-row actions for a single dividend timeline event.
///
/// A dividend cash event maps to exactly one journal entry
/// ([DividendCenterEvent.event.journalEntryId]), so we reuse the existing
/// journal-entry surfaces rather than build a parallel editor:
///   * **View in activity** → the read-only [ActivityEntryDetailPage].
///   * **Edit** → re-record via the corporate-action form (there is no
///     in-place dividend editor; the expense form's 2-posting shape would
///     corrupt a 3-leg dividend with withholding).
///   * **Delete** → [JournalEntryRepository.softDelete]; the dividend
///     center snapshot re-derives from the journal stream and refreshes.
Future<void> showDividendEventActions(
  BuildContext context,
  WidgetRef ref,
  DividendCenterEvent event,
) {
  final l10n = AppLocalizations.of(context);
  final formatters = context.formatters(ref);
  return showAppSheet<void>(
    context: context,
    title: l10n.dividendEventActionsTitle,
    subtitle: '${event.assetLabel} · ${formatters.date(event.event.date)}',
    builder: (sheetContext) => AppActionSheetList(
      children: [
        AppActionSheetTile(
          icon: Icons.receipt_long_outlined,
          title: l10n.dividendEventViewInActivity,
          subtitle: l10n.dividendEventViewInActivityHint,
          onPress: () {
            Navigator.of(sheetContext).pop();
            _viewInActivity(context, ref, event);
          },
        ),
        AppActionSheetTile(
          icon: Icons.edit_outlined,
          title: l10n.dividendEventEdit,
          subtitle: l10n.dividendEventEditHint,
          onPress: () {
            Navigator.of(sheetContext).pop();
            context.push(AppRoutes.wealthCorporateAction);
          },
        ),
        AppActionSheetTile(
          icon: Icons.delete_outline,
          title: l10n.commonDelete,
          subtitle: l10n.dividendEventDeleteHint,
          onPress: () {
            Navigator.of(sheetContext).pop();
            _deleteDividendEntry(context, ref, event);
          },
        ),
      ],
    ),
  );
}

Future<void> _viewInActivity(
  BuildContext context,
  WidgetRef ref,
  DividendCenterEvent event,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final repo = await ref.read(journalEntryRepositoryProvider.future);
    final entry = await repo.getById(event.event.journalEntryId);
    final accounts = await ref.read(allAccountsStreamProvider.future);
    if (entry == null) {
      if (context.mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.dividendEventOpenFailed,
        );
      }
      return;
    }
    if (!context.mounted) return;
    final args = ActivityEntryDetailArgs(
      entry: entry,
      accountsById: {for (final account in accounts) account.id: account},
    );
    unawaited(
      context.pushNamed(
        AppRouteNames.activityEntryDetail,
        pathParameters: {'entryId': entry.entry.id},
        extra: args,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.dividendEventOpenFailed);
    }
  }
}

Future<void> _deleteDividendEntry(
  BuildContext context,
  WidgetRef ref,
  DividendCenterEvent event,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(l10n.dividendEventDeleteTitle),
    body: Text(l10n.dividendEventDeleteBody(event.assetLabel)),
    confirmLabel: l10n.commonDelete,
    cancelLabel: l10n.commonCancel,
    destructive: true,
  );
  if (confirmed != true) return;
  try {
    final repo = await ref.read(journalEntryRepositoryProvider.future);
    await repo.softDelete(event.event.journalEntryId);
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.dividendEventDeleted);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.dividendEventDeleteFailed,
      );
    }
  }
}
