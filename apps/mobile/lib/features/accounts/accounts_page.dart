import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../app/master_detail_layout.dart';
import '../../app/selection_query.dart';
import '../../data/domain/enums.dart';
import 'account_form_page.dart';
import 'ui/accounts_master.dart';

/// Lists every active account, grouped by [AccountCategory].
///
/// Tapping an account opens its edit form; the floating action button
/// creates a new one. Soft-deleted / archived accounts hide here — the
/// archived-accounts surface is intentionally separate so the primary list
/// stays focused on the user's day-to-day book of accounts.
///
/// At desktop width (≥ 1240) the page renders as a master-detail surface
/// (FIR-106): the list lives on the left, and the account edit form for
/// the `?selected=<id>` row lives on the right.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key, this.embedded = false});

  /// When true, skips the Scaffold so the page can be embedded
  /// inside another Scaffold (e.g., the Activity tab).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final masterDetail = MasterDetailLayout.shouldUseMasterDetail(
          constraints.maxWidth,
        );
        final selected = selectedQueryOf(context);
        if (masterDetail) {
          return FScaffold(
            childPad: false,
            child: Material(
              color: Colors.transparent,
              child: MasterDetailLayout(
                master: AccountsMaster(
                  selectedId: selected,
                  inMasterDetail: true,
                ),
                detail: selected == null
                    ? const AccountsDetailEmpty()
                    : AccountFormPage(accountId: selected),
              ),
            ),
          );
        }
        return AccountsMaster(
          selectedId: null,
          inMasterDetail: false,
          embedded: embedded,
        );
      },
    );
  }
}
