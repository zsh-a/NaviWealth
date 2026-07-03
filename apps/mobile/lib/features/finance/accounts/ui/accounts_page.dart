import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import 'account_form_page.dart';
import 'accounts_master.dart';

/// Lists every active account, grouped by [AccountCategory].
///
/// Tapping an account opens its edit form; the floating action button
/// creates a new one. Soft-deleted / archived accounts hide here — the
/// archived-accounts surface is intentionally separate so the primary list
/// stays focused on the user's day-to-day book of accounts.
///
/// At desktop width (≥ 1240) the page renders as a master-detail surface:
/// the list lives on the left, and the account edit form for
/// the `?selected=<id>` row lives on the right.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final masterDetail = MasterDetailLayout.shouldUseMasterDetail(
          constraints.maxWidth,
        );
        final selected = selectedQueryOf(context);
        if (masterDetail) {
          return AppCanvasScaffold(
            childPad: false,
            child: MasterDetailLayout(
              master: AccountsMaster(
                selectedId: selected,
                inMasterDetail: true,
              ),
              detail: selected == null
                  ? const AccountsDetailEmpty()
                  : AccountFormPage(accountId: selected),
            ),
          );
        }
        return const AccountsMaster(selectedId: null, inMasterDetail: false);
      },
    );
  }
}
