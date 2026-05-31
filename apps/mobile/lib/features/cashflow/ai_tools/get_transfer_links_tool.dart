/// `get_transfer_links` — device port (Analytical).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/get_transfer_links.rs`. Per §4.3.3 the
/// device `transferMatcher` is the sole computer; the backend
/// `transfer_links` read model mirrors what the device uploaded. The
/// tool runs the same matcher + the shared [transferMatchToUpload]
/// converter (single source with the cloud upload) and projects into
/// the backend row shape — no D1, no freshness gate.
library;

import 'package:naviwealth/core/ai/contracts/task_context.dart' show AnalyticalUpload;
import 'package:naviwealth/core/ai/local/skills/skills.dart';
import 'package:naviwealth/features/finance/ai_tools/expense_to_transaction_input.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';

class GetTransferLinksTool implements DeviceTool {
  const GetTransferLinksTool();

  @override
  String get name => 'get_transfer_links';

  @override
  String get description =>
      '返回端侧 transferMatcher 检测到的「账户 A → 账户 B」转账配对。'
      '数据来自 AI Read Model `transfer_links`（Analytical P1，device-sourced）。'
      'payload 含 from_txn_id / to_txn_id / amount_minor / currency。'
      '典型问题：「最近转了几笔」「哪些钱在不同账户之间挪动」。'
      '这些配对是端侧启发式匹配（同币种 + ±2 天窗口 + 50 minor 容差）。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'currency': {'type': 'string', 'description': '可选；只看某一币种。'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final List<Expense> expenses = await ctx.ref.read(
      journalExpensesStreamProvider.future,
    );
    final uploads = [
      for (final m in matchTransfers(expenses.map(expenseToTransactionInput)))
        transferMatchToUpload(m),
    ];
    return shape(
      uploads,
      currency: input['currency'] is String
          ? input['currency'] as String
          : null,
    );
  }

  /// Pure projection into the backend `get_transfer_links` envelope +
  /// the same `currency` filter as the read model `query_all`.
  static Map<String, Object?> shape(
    List<AnalyticalUpload> uploads, {
    String? currency,
  }) {
    final ccy = (currency != null && currency.trim().isNotEmpty)
        ? currency.trim().toUpperCase()
        : null;
    final links = <Map<String, Object?>>[];
    for (final u in uploads) {
      final p = u.payload;
      final rowCcy = p['currency'] as String?;
      if (ccy != null && (rowCcy?.toUpperCase() ?? '') != ccy) continue;
      links.add(<String, Object?>{
        'id': u.id,
        'from_txn_id': p['from_txn_id'],
        'to_txn_id': p['to_txn_id'],
        'amount_minor': p['amount_minor'],
        'currency': rowCcy,
        'payload': p,
      });
    }
    return <String, Object?>{
      'links': links,
      'count': links.length,
      'source': 'device_analytical_read_model',
      'note':
          'device-sourced：端侧 transferMatcher 检测（同币种 + ±2 天窗口 + 50 minor 容差）。'
          '空结果可能是端侧没检到。',
    };
  }
}
