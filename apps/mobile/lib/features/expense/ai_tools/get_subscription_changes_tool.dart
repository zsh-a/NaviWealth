/// `get_subscription_changes` — device port.
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/get_subscription_changes.rs`. Per §4.3.3
/// the device `detectSubscriptionChanges` is the sole computer; the
/// backend `subscription_changes` read model mirrors what the device
/// uploaded. The tool runs the same detector + the shared
/// [subscriptionChangeToUpload] converter (single source with the
/// cloud upload) and projects into the backend row shape — no D1, no
/// freshness gate. Detection window is the expenses on hand (no
/// cross-session persistence), same as the backend note.
library;

import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;
import 'package:naviwealth/core/ai/local/skills/skills.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/expense_to_transaction_input.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';

class GetSubscriptionChangesTool implements DeviceTool {
  const GetSubscriptionChangesTool();

  @override
  String get name => 'get_subscription_changes';

  @override
  String get description =>
      '返回端侧 detectSubscriptionChanges 检测到的订阅价格变动'
      '（早窗口 median vs 晚窗口 median 差值超 10% 且 >=\$1 等价）。'
      '数据来自 AI Read Model `subscription_changes`（Analytical P1，device-sourced）。'
      'payload 含 merchant_key / cadence / currency / prev_amount_minor / '
      'new_amount_minor / delta_ratio / since。'
      '典型问题：「哪些订阅最近涨价了」「Netflix 涨了多少」。'
      '注意：检测窗口仅限于本次 chat 上报的 expenses，未持久化跨会话状态。';

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
      for (final c in detectSubscriptionChanges(
        expenses.map(expenseToTransactionInput),
      ))
        subscriptionChangeToUpload(c),
    ];
    return shape(
      uploads,
      currency: input['currency'] is String
          ? input['currency'] as String
          : null,
    );
  }

  /// Pure projection into the backend `get_subscription_changes`
  /// envelope + the same `currency` filter as the read model
  /// `query_all`.
  static Map<String, Object?> shape(
    List<AnalyticalUpload> uploads, {
    String? currency,
  }) {
    final ccy = (currency != null && currency.trim().isNotEmpty)
        ? currency.trim().toUpperCase()
        : null;
    final changes = <Map<String, Object?>>[];
    for (final u in uploads) {
      final p = u.payload;
      final rowCcy = p['currency'] as String?;
      if (ccy != null && (rowCcy?.toUpperCase() ?? '') != ccy) continue;
      changes.add(<String, Object?>{
        'id': u.id,
        'merchant_key': p['merchant_key'],
        'cadence': p['cadence'],
        'currency': rowCcy,
        'prev_amount_minor': p['prev_amount_minor'],
        'new_amount_minor': p['new_amount_minor'],
        'delta_ratio': p['delta_ratio'],
        'since': p['since'],
        'payload': p,
      });
    }
    return <String, Object?>{
      'changes': changes,
      'count': changes.length,
      'source': 'device_analytical_read_model',
      'note':
          'device-sourced：端侧 detectSubscriptionChanges 在本次 chat 上报的 expense 窗口内对比 '
          'earlier vs later median。跨会话历史需要 OpLog 持久化 recurring_patterns 后扩展。',
    };
  }
}
