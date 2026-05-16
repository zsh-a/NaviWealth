/// `list_payment_accounts` — device port (§4.6 W-D4).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/list_payment_accounts.rs`. The backend
/// scans the D1 `accounts` table + JSON payload; here we read the same
/// truth from Drift via `accountsStreamProvider` (already
/// active-only + system/deleted-excluded — matching the backend
/// `deleted_at IS NULL AND id NOT LIKE 'system-account:%'`), then apply
/// the identical payload filter (asset-side, non-archived, not the
/// generic `asset` container) so the output shape is byte-identical.
library;

import '../../../../../data/domain/account.dart';
import '../../../../../data/domain/enums.dart';
import '../../../../../data/repositories/providers.dart';
import 'device_tool.dart';

class ListPaymentAccountsTool implements DeviceTool {
  const ListPaymentAccountsTool();

  @override
  String get name => 'list_payment_accounts';

  @override
  String get description =>
      '列出可用于记录支出的支付账户候选。只在用户要记消费但没有指定支付账户时调用；'
      '返回非系统、未归档、未删除的资产侧账户（现金 / 银行 / 券商 / 加密等），可按币种过滤。'
      '如果返回空，再询问用户要创建哪种支付账户。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['purpose'],
    'properties': {
      'purpose': {
        'type': 'string',
        'enum': ['record_expense', 'account_selection'],
        'description': '调用目的；用于审计和约束模型只在选择支付账户时读取。',
      },
      'currency': {
        'type': 'string',
        'description': '可选；按账户币种过滤，例如 CNY。',
      },
      'max_results': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'default': 8,
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final purpose = input['purpose'];
    if (purpose is! String ||
        (purpose != 'record_expense' && purpose != 'account_selection')) {
      return <String, Object?>{
        'error':
            "list_payment_accounts: unsupported purpose '${purpose ?? ''}'",
        'code': 'bad_request',
      };
    }

    final accounts = await ctx.ref.read(accountsStreamProvider.future);
    return shape(
      accounts,
      purpose: purpose,
      currency: input['currency'] is String
          ? input['currency'] as String
          : null,
      maxResults: input['max_results'] is num
          ? (input['max_results'] as num).toInt()
          : 8,
    );
  }

  /// Pure filter + sort + shape (separated from the provider read so it
  /// is unit-tested directly). `accountsStreamProvider` already excludes
  /// system + deleted accounts, matching the backend SQL `WHERE`; this
  /// applies the identical payload-level filter so the JSON is
  /// byte-identical to `list_payment_accounts.rs`.
  static Map<String, Object?> shape(
    List<Account> accounts, {
    required String purpose,
    String? currency,
    int maxResults = 8,
  }) {
    final currencyFilter = (currency != null && currency.trim().isNotEmpty)
        ? currency.trim().toUpperCase()
        : null;
    final limit = maxResults.clamp(1, 20);

    final candidates =
        accounts.where((a) {
          if (a.archived) return false;
          if (a.category != AccountSide.asset) return false;
          // Exclude the generic manual-valuation `asset` container —
          // matches the backend `payload.type == "asset"` exclusion.
          if (a.type == AccountCategory.asset) return false;
          if (currencyFilter != null &&
              a.currency.toUpperCase() != currencyFilter) {
            return false;
          }
          return true;
        }).toList()
        ..sort((a, b) {
          final byName = a.name.compareTo(b.name);
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });

    final total = candidates.length;
    final values = [
      for (final a in candidates.take(limit))
        <String, Object?>{
          'id': a.id,
          'name': a.name,
          'type': a.type.name,
          'currency': a.currency,
        },
    ];

    return <String, Object?>{
      'status': 'ready',
      'purpose': purpose,
      'currency_filter': currencyFilter,
      'total_count': total,
      'truncated': total > values.length,
      'accounts': values,
      'note':
          '这些是可作为支出支付来源的账户；如果用户没有指定支付账户，'
          '请让用户从候选里选择，或用 account_id 调用 propose_expense。',
    };
  }
}
