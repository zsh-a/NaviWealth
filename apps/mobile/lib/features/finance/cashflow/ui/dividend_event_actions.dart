import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_entry_detail_page.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
List<AppAdaptiveAction> buildDividendEventActions(
  BuildContext context,
  WidgetRef ref,
  DividendCenterEvent event,
) {
  final l10n = AppLocalizations.of(context);
  return <AppAdaptiveAction>[
    AppAdaptiveAction(
      icon: FLucideIcons.receipt,
      title: l10n.dividendEventViewInActivity,
      subtitle: l10n.dividendEventViewInActivityHint,
      onPress: () {
        if (context.mounted) return _viewInActivity(context, ref, event);
      },
    ),
    AppAdaptiveAction(
      icon: FLucideIcons.pencil,
      title: l10n.dividendEventEdit,
      subtitle: l10n.dividendEventEditHint,
      onPress: () {
        if (context.mounted) {
          context.push(FinanceRoutes.wealthCorporateAction);
        }
      },
    ),
    AppAdaptiveAction(
      icon: FLucideIcons.trash2,
      title: l10n.commonDelete,
      subtitle: l10n.dividendEventDeleteHint,
      destructive: true,
      onPress: () {
        if (context.mounted) {
          return _deleteDividendEntry(context, ref, event);
        }
      },
    ),
  ];
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
        FinanceRouteNames.activityEntryDetail,
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
