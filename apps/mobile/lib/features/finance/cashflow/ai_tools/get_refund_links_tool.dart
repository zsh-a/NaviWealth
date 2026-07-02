/// `get_refund_links` — device port (Analytical).
///
/// Schema + description verbatim from
/// the historical backend `get_refund_links` tool. Per §4.3.3 the
/// device `refundMatcher` is the sole computer; the `refund_links`
/// read-model shape is derived from the same device analytical signal.
/// The tool runs the same matcher + the shared [refundMatchToUpload]
/// converter (single source) and projects into the row shape — no D1,
/// no freshness gate.
library;

import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;
import 'package:naviwealth/core/ai/local/skills/skills.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/expense_to_transaction_input.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';

class GetRefundLinksTool implements DeviceTool {
  const GetRefundLinksTool();

  @override
  String get name => 'get_refund_links';

  @override
  String get description =>
      '返回端侧 refundMatcher 检测到的「原交易 ↔ 退款」配对。'
      '数据来自 AI Read Model `refund_links`（Analytical P1，device-sourced）。'
      'payload 含 original_txn_id / refund_txn_id / amount_minor / currency。'
      '典型问题：「哪些退款还在路上」「最近退了多少」「这笔退款对应哪次买入」。';

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
      for (final m in matchRefunds(expenses.map(expenseToTransactionInput)))
        refundMatchToUpload(m),
    ];
    return shape(
      uploads,
      currency: input['currency'] is String
          ? input['currency'] as String
          : null,
    );
  }

  /// Pure projection into the backend `get_refund_links` envelope +
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
        'original_txn_id': p['original_txn_id'],
        'refund_txn_id': p['refund_txn_id'],
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
          'device-sourced：端侧 refundMatcher 检测，本工具按 AnalyticalUpload shape 投影。'
          '空结果可能是端侧没检到或没退款。',
    };
  }
}
