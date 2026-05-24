/// `get_recurring_patterns` — device port (§4.6 W-D4.3b, Analytical).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/get_recurring_patterns.rs`. Per §4.3.3
/// the device `recurring_detector` is the **sole computer** — the
/// backend `recurring_patterns` read model is a mirror of what the
/// device uploaded via `ContextPack.analytical_uploads`. So the device
/// tool runs the same detector and the shared
/// [recurringPatternToUpload] converter (single source with the cloud
/// upload, no Dart/Rust drift) and projects the uploads into the
/// backend row shape — byte-identical, no D1, no freshness gate.
library;

import '../../../../../data/domain/expense.dart';
import '../../../../../data/repositories/journal_entry_providers.dart';
import '../../../contracts/task_context.dart' show AnalyticalUpload;
import '../../../local/skills/skills.dart';
import 'device_tool.dart';

class GetRecurringPatternsTool implements DeviceTool {
  const GetRecurringPatternsTool();

  @override
  String get name => 'get_recurring_patterns';

  @override
  String get description =>
      '返回端侧 detector 检测到的周期性支出（月度/周度订阅、定期账单等）。'
      '数据来自 AI Read Model `recurring_patterns`（Analytical 层 P1）—— '
      '这是 device-sourced read model：端侧 recurring_detector 跑启发式产生，'
      '通过 ContextPack.analytical_uploads 镜像到云端表（避免 Dart/Rust 双份漂移）。'
      '典型问题：「我有哪些订阅」「每月定期支出多少」「哪些订阅最近涨价了」（最后这个需配合 subscription_changes，待落）。'
      '可选 currency / cadence 过滤。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'currency': {'type': 'string', 'description': '可选；只看某一币种。'},
      'cadence': {
        'type': 'string',
        'enum': ['weekly', 'monthly'],
        'description': '可选；只看某一周期。',
      },
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
      for (final p in detectRecurring(expenses.map(expenseToTransactionInput)))
        recurringPatternToUpload(p),
    ];
    return shape(
      uploads,
      currency: input['currency'] is String
          ? input['currency'] as String
          : null,
      cadence: input['cadence'] is String ? input['cadence'] as String : null,
    );
  }

  /// Pure projection of the device recurring [AnalyticalUpload]s into
  /// the backend `get_recurring_patterns` envelope + the same
  /// `currency` / `cadence` filter as the read model `query_all`.
  static Map<String, Object?> shape(
    List<AnalyticalUpload> uploads, {
    String? currency,
    String? cadence,
  }) {
    final ccy = (currency != null && currency.trim().isNotEmpty)
        ? currency.trim().toUpperCase()
        : null;
    final cad = (cadence == 'weekly' || cadence == 'monthly') ? cadence : null;

    final patterns = <Map<String, Object?>>[];
    for (final u in uploads) {
      final p = u.payload;
      final rowCcy = p['currency'] as String?;
      if (ccy != null && (rowCcy?.toUpperCase() ?? '') != ccy) continue;
      if (cad != null && p['cadence'] != cad) continue;
      patterns.add(<String, Object?>{
        'id': u.id,
        'merchant_key': p['merchant_key'],
        'cadence': p['cadence'],
        'currency': rowCcy,
        'median_amount_minor': p['median_amount_minor'],
        'occurrences': p['occurrences'],
        'last_seen_at': p['last_seen_at'],
        'payload': p,
      });
    }
    return <String, Object?>{
      'patterns': patterns,
      'count': patterns.length,
      'source': 'device_analytical_read_model',
      'note':
          'device-sourced：端侧 recurring_detector 检测，通过 ContextPack.analytical_uploads 上报。'
          '当结果为空时，可能是端侧还没上报过 / 端侧检测不到稳定周期 / 用户没有订阅。',
    };
  }
}
