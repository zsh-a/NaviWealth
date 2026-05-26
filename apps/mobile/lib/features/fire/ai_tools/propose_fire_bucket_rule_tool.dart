import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/_shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/fire/domain/fire_bucket.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

/// `propose_fire_bucket_rule` — propose assigning an asset (or
/// account) to a FIRE bucket role.
///
/// Like every other `propose_*` tool, the result must pass through the
/// front-end's confirmation pipeline before any mapping is persisted.
class ProposeFireBucketRuleTool implements DeviceTool {
  const ProposeFireBucketRuleTool();

  @override
  String get name => 'propose_fire_bucket_rule';

  @override
  String get description =>
      '提议把一个资产或账户分配到某个 FIRE 桶(cash / defensive / growth / risk_reserve / dream)。'
      '本工具不会立即写入——返回 plan 让用户确认后再落地。'
      '`target_id` 必须存在;若用名字模糊指代,可能拿到 needs_clarification(请用户选具体一个)。'
      '禁止用本工具表达"现金桶"或"风险桶"的目标值;那些字段属于 FIRE plan,请用 propose_fire_plan_update。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'required': <String>['role', 'target_id'],
    'properties': <String, Object?>{
      'role': <String, Object?>{
        'type': 'string',
        'enum': <String>[
          'cash',
          'defensive',
          'growth',
          'risk_reserve',
          'dream',
        ],
      },
      'target_id': <String, Object?>{
        'type': 'string',
        'description': '资产或账户的 id。',
      },
      'target_table': <String, Object?>{
        'type': 'string',
        'enum': <String>['accounts', 'assets'],
        'description': '默认 assets。',
      },
      'allocation_pct': <String, Object?>{
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
      },
      'note': <String, Object?>{'type': 'string'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final roleRaw = input['role'];
    if (roleRaw is! String) {
      return proposalBadRequest("missing or non-string field 'role'");
    }
    final role = _roleFromWire(roleRaw);
    if (role == null) {
      return proposalBadRequest("unknown role '$roleRaw'");
    }
    final targetId = input['target_id'];
    if (targetId is! String || targetId.isEmpty) {
      return proposalBadRequest("missing or non-string field 'target_id'");
    }
    final targetTable = (input['target_table'] as String?) ?? 'assets';
    if (targetTable != 'assets' && targetTable != 'accounts') {
      return proposalBadRequest("unknown target_table '$targetTable'");
    }
    final pctRaw = input['allocation_pct'];
    final pct = pctRaw is num ? pctRaw.toDouble().clamp(0.0, 1.0) : null;
    final note = input['note'] as String?;

    // Verify the target exists. We use the typed lists to look up;
    // missing targets return a bad_request so the AI can ask the user
    // to clarify rather than persisting a dangling rule.
    final found = await _exists(ctx, targetTable, targetId);
    if (!found) {
      return proposalBadRequest(
        "target_id '$targetId' not found in '$targetTable'",
      );
    }

    final payload = <String, Object?>{
      'role': role.name,
      'target_table': targetTable,
      'target_id': targetId,
      'allocation_pct': ?pct,
      'note': ?note,
    };
    return readyPlan(
      kind: 'fire_bucket_rule',
      summaryZh: _summary(role, targetId, pct),
      payload: payload,
    );
  }
}

FireBucketRole? _roleFromWire(String wire) {
  switch (wire) {
    case 'cash':
      return FireBucketRole.cash;
    case 'defensive':
      return FireBucketRole.defensive;
    case 'growth':
      return FireBucketRole.growth;
    case 'risk_reserve':
      return FireBucketRole.riskReserve;
    case 'dream':
      return FireBucketRole.dream;
  }
  return null;
}

Future<bool> _exists(DeviceToolContext ctx, String table, String id) async {
  switch (table) {
    case 'assets':
      final assets = await ctx.ref.read(allAssetsStreamProvider.future);
      return assets.any((a) => a.id == id);
    case 'accounts':
      final accounts = await ctx.ref.read(allAccountsStreamProvider.future);
      return accounts.any((a) => a.id == id);
  }
  return false;
}

String _summary(FireBucketRole role, String targetId, double? pct) {
  final pctPart = pct != null ? '(${(pct * 100).toStringAsFixed(0)}%)' : '';
  return '把 $targetId 分配到桶 ${role.name}$pctPart';
}
