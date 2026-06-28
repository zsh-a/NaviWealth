/// `propose_routine` — KnowledgeOS device write tool
/// (`docs/domains/knowledgeos-domain.md` §4 + §7).
///
/// **Write semantics**: returns a proposal envelope; the user must
/// confirm in the UI before the row lands. Matches the cross-domain
/// `propose_*` pattern.
///
/// AI surfaces this when natural-language input describes a recurring
/// reminder ("港卡每 6 个月活跃一次" / "记得每年报税" / "每周做一次 portfolio
/// 复盘"). The reasoning model picks a sensible interval; the user
/// confirms or edits before commit.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '_tool_support.dart';

class ProposeRoutineTool implements DeviceTool {
  const ProposeRoutineTool();

  @override
  String get name => 'propose_routine';

  @override
  String get description =>
      '建议新建一条 Knowledge Routine(定期提醒)。**不会**直接写库,返回 proposal envelope,'
      '前端显示 summary_zh 让用户一键确认。'
      '适用:用户表达「每 X 时间做一次 Y」、「每隔 X 个月 / 每年都需要 …」、'
      '「Z 需要定期活跃 / 续期 / 缴费」等周期性事项。'
      'interval_days 必须 > 0;next_due_at 可选(默认 now + interval_days);'
      'scope 自由 tag(例如 "finance/cards/hk")用于后续过滤。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'statement': {
        'type': 'string',
        'description': '一句话描述要做什么(例:"港卡做一次活跃交易")。',
      },
      'interval_days': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 3650,
        'description': '周期天数(180 = 6 个月,365 = 1 年)。',
      },
      'scope': {
        'type': 'string',
        'description': '可选自由 tag,用作过滤(例如 "finance/cards/hk")。默认 "*"。',
      },
      'next_due_at': {
        'type': 'string',
        'description': '可选 ISO8601 首次到期日;默认 now + interval_days。',
      },
      'reason': {
        'type': 'string',
        'description': '一句中文说明为什么建议建这条 Routine。会显示给用户。',
      },
    },
    'required': <String>['statement', 'interval_days', 'reason'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final statement = (input['statement'] as String?)?.trim() ?? '';
    final intervalDays = (input['interval_days'] as num?)?.toInt() ?? 0;
    final scope = (input['scope'] as String?)?.trim().isNotEmpty == true
        ? (input['scope'] as String).trim()
        : '*';
    final reason = (input['reason'] as String?)?.trim() ?? '';
    final nextDueRaw = (input['next_due_at'] as String?)?.trim() ?? '';

    if (statement.isEmpty || reason.isEmpty || intervalDays <= 0) {
      return badRequest('statement / reason 必填,interval_days 必须 > 0。');
    }
    if (intervalDays > 3650) {
      return badRequest('interval_days 上限 3650(约 10 年)。');
    }

    final now = DateTime.now().toUtc();
    final defaultNextDue = now.add(Duration(days: intervalDays));
    final nextDue = DateTime.tryParse(nextDueRaw) ?? defaultNextDue;

    final humanInterval = _humanInterval(intervalDays);
    final summary = '建议新建 Routine:"$statement" 每 $humanInterval 一次 — $reason';

    return proposalEnvelope(
      kind: 'knowledge_routine',
      summaryZh: summary,
      payload: <String, Object?>{
        'statement': statement,
        'interval_days': intervalDays,
        'scope': scope,
        'next_due_at': nextDue.toUtc().toIso8601String(),
        'reason': reason,
      },
      note: '前端必须显示 summary_zh 给用户确认；只有用户明确点确认后才走 Repository.upsertRoutine。',
    );
  }

  static String _humanInterval(int days) {
    if (days % 365 == 0 && days >= 365) {
      final years = days ~/ 365;
      return years == 1 ? '年' : '$years 年';
    }
    if (days % 30 == 0 && days >= 30) {
      final months = days ~/ 30;
      return months == 1 ? '月' : '$months 个月';
    }
    if (days % 7 == 0 && days >= 7) {
      final weeks = days ~/ 7;
      return weeks == 1 ? '周' : '$weeks 周';
    }
    return '$days 天';
  }
}
