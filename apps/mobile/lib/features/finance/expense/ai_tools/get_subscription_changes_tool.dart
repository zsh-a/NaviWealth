/// `get_subscription_changes` — device port.
///
/// Schema + description verbatim from
/// the historical backend `get_subscription_changes` tool. Per §4.3.3
/// the device `detectSubscriptionChanges` is the sole computer; the
/// `subscription_changes` read-model shape is derived from the same
/// device analytical signal. The tool runs the same detector + the
/// shared [subscriptionChangeToUpload] converter (single source) and
/// projects into the row shape — no D1, no freshness gate. Detection uses the
/// current expense window plus local-only recurring-pattern observations
/// persisted in Drift.
library;

import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/finance/ai_tools/expense_to_transaction_input.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/expense/data/recurring_pattern_history_store.dart';

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
      '当前 expense 窗口会刷新本地 recurring-pattern observation log，'
      '历史 observation 用于跨会话比较。';

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
    final txns = expenses.map(expenseToTransactionInput).toList();
    final patterns = detectRecurring(txns);
    final ownerUserId = await _recordPatternHistoryBestEffort(ctx, patterns);
    final liveChanges = detectSubscriptionChanges(txns);
    final historicalChanges = ownerUserId == null
        ? const <SubscriptionChange>[]
        : await _readHistoricalChangesBestEffort(ctx, ownerUserId);
    final byId = <String, SubscriptionChange>{
      for (final c in liveChanges) '${c.merchantKey}|${c.currency}': c,
      for (final c in historicalChanges) '${c.merchantKey}|${c.currency}': c,
    };
    final uploads = [
      for (final c in byId.values) subscriptionChangeToUpload(c),
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
          'device-sourced：端侧 detectSubscriptionChanges 对比当前 expense 窗口，'
          '并结合 local-only recurring-pattern observation log 做跨会话 old-vs-new median 比较。',
    };
  }

  static Future<String?> _recordPatternHistoryBestEffort(
    DeviceToolContext ctx,
    List<RecurringPattern> patterns,
  ) async {
    try {
      final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
      if (patterns.isNotEmpty) {
        final db = await ctx.ref.read(appDatabaseProvider.future);
        await RecurringPatternHistoryStore(db).recordPatterns(
          ownerUserId: ownerUserId,
          observedAt: DateTime.now().toUtc(),
          patterns: patterns,
        );
      }
      return ownerUserId;
    } on Object {
      return null;
    }
  }

  static Future<List<SubscriptionChange>> _readHistoricalChangesBestEffort(
    DeviceToolContext ctx,
    String ownerUserId,
  ) async {
    try {
      final db = await ctx.ref.read(appDatabaseProvider.future);
      return RecurringPatternHistoryStore(
        db,
      ).detectHistoricalChanges(ownerUserId: ownerUserId);
    } on Object {
      return const <SubscriptionChange>[];
    }
  }
}
