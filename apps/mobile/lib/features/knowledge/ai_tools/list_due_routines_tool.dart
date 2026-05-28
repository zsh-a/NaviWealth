/// `list_due_routines` — KnowledgeOS device tool
/// (`docs/knowledgeos-domain.md` §4 + §7).
///
/// Returns active routines whose `next_due_at <= as_of`, including those
/// already overdue. Used by Morning Briefing / Review tab / RoutineDueAgent.
/// `as_of` defaults to `now + 7d` so the caller sees "this week" without
/// re-doing the arithmetic; pass an explicit ISO8601 to narrow.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';

class ListDueRoutinesTool implements DeviceTool {
  const ListDueRoutinesTool();

  @override
  String get name => 'list_due_routines';

  @override
  String get description =>
      '列出所有 status=active 且 next_due_at <= as_of 的 Routine(用户自定义的定期提醒,'
      '例如「港卡每 6 个月活跃一次」)。每条返回 id / statement / interval_days / '
      'next_due_at / last_done_at / days_until_due(负数代表已逾期)。'
      'as_of 默认 now+7d(本周窗口),可传 ISO8601 缩小或扩大。'
      '用途:Review tab、Morning Briefing、回答「我现在有什么定期事项要做？」。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'as_of': {
        'type': 'string',
        'description': 'ISO8601 截止时间;默认 now + 7 天(本周窗口)。',
      },
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 200,
        'default': 50,
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final now = DateTime.now().toUtc();
    final asOf =
        DateTime.tryParse((input['as_of'] as String?) ?? '') ??
        now.add(const Duration(days: 7));
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 200)
        : 50;

    final due = await repo.listDueRoutines(
      ownerUserId: ownerUserId,
      asOf: asOf,
      limit: limit,
    );

    return <String, Object?>{
      'as_of': asOf.toUtc().toIso8601String(),
      'routines': due
          .map(
            (r) => <String, Object?>{
              'id': r.id,
              'statement': r.statement,
              'interval_days': r.intervalDays,
              'scope': r.scope,
              'next_due_at': r.nextDueAt.toUtc().toIso8601String(),
              'last_done_at': r.lastDoneAt?.toUtc().toIso8601String(),
              'days_until_due': r.daysUntilDue(now),
            },
          )
          .toList(growable: false),
    };
  }
}
