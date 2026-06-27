/// `list_due_reviews` — KnowledgeOS device tool
/// (`docs/domains/knowledgeos-domain.md` §4).
///
/// Weekly Review 主面板。Returns decisions whose `review_date <= as_of`
/// and status is still pending verification.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';

class ListDueReviewsTool implements DeviceTool {
  const ListDueReviewsTool();

  @override
  String get name => 'list_due_reviews';

  @override
  String get description =>
      '列出所有 review_date 已到期(或在 as_of 之前)且 status 仍是 draft/active/paused 的 '
      'Decision。每条返回 id / question / status / review_date / days_overdue / age_days。'
      '用途:Weekly Review / Review tab / ReviewAgent。'
      '可选 as_of (ISO8601),默认 now。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'as_of': {'type': 'string', 'description': 'ISO8601 截止时间;默认 now。'},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 200, 'default': 50},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final asOf =
        DateTime.tryParse((input['as_of'] as String?) ?? '') ??
        DateTime.now().toUtc();
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 200)
        : 50;

    final due = await repo.listDueReviews(
      ownerUserId: ownerUserId,
      asOf: asOf,
      limit: limit,
    );

    final now = DateTime.now().toUtc();
    return <String, Object?>{
      'decisions': due
          .map(
            (d) => <String, Object?>{
              'id': d.id,
              'question': d.question,
              'selected': d.selectedLabel,
              'status': d.status.wire,
              'review_date': d.reviewDate?.toUtc().toIso8601String(),
              'days_overdue': d.daysOverdue(asOf),
              'age_days': now.difference(d.decidedAt.toUtc()).inDays,
            },
          )
          .toList(growable: false),
    };
  }
}
