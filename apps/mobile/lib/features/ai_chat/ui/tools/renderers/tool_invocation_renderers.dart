import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../../../core/format/formatters.dart';
import '../../../../../design_system/design_system.dart';
import '../../../../../l10n/gen/app_localizations.dart';
import '../../ai_navigation.dart';

part 'asset_allocation.dart';
part 'analytical_lists.dart';
part 'holdings.dart';
part 'performance.dart';
part 'breakdowns.dart';

/// Maximum number of rows a list-style renderer will draw before
/// collapsing the rest behind a "+ N 项" hint. Keeps the assistant
/// reply readable when the model pulls back hundreds of ledger rows.
const int _kMaxVisibleRows = 10;

/// Above this raw row count we never fully expand inline — the user can
/// still drop into raw JSON if they need every entry. Mirrors the spec:
/// > 数据过大（> 50 条）→ 截断显示前 10 + 提示
const int _kRawListLimit = 50;

/// Tools whose output is a primary visual answer (chart / KPI card).
/// Higher priority first — used to pin one artifact above collapsed steps.
const List<String> kRichVisualizationTools = <String>[
  'get_net_worth_summary',
  'compute_net_worth',
  'get_asset_allocation',
  'compute_xirr',
  'get_holdings',
  'get_industry_breakdown',
  'get_geo_breakdown',
  'get_market_cap_breakdown',
  'get_risk_alerts',
  'get_recurring_patterns',
  'get_subscription_changes',
  'get_refund_links',
  'list_payment_accounts',
];

/// Whether [toolName] has a specialized domain renderer registered.
bool isRichToolOutput(String toolName, Object? output) {
  if (output == null) return false;
  return switch (toolName) {
    'get_holdings' ||
    'list_payment_accounts' ||
    'compute_xirr' ||
    'compute_net_worth' ||
    'get_net_worth_summary' ||
    'get_industry_breakdown' ||
    'get_geo_breakdown' ||
    'get_market_cap_breakdown' ||
    'get_risk_alerts' ||
    'get_asset_allocation' ||
    'get_recurring_patterns' ||
    'get_subscription_changes' ||
    'get_refund_links' => true,
    _ => false,
  };
}

/// Priority score for pinning a visualization (lower = more important).
int richToolPriority(String toolName) {
  final i = kRichVisualizationTools.indexOf(toolName);
  return i < 0 ? 999 : i;
}

/// Soft answer surface shared by tool result cards in the chat timeline.
class ToolResultSurface extends StatelessWidget {
  const ToolResultSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.s12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SoftCard.raised(
      padding: padding,
      borderRadius: AppRadius.md,
      child: child,
    );
  }
}

/// Build a specialised body widget for the `output` of [toolName]. Returns
/// `null` when no renderer is registered for the tool, when the payload
/// is the wrong shape, or when an exception is raised mid-render — the
/// caller should fall back to the pretty-printed JSON in that case.
///
/// The renderers are intentionally pure (no Riverpod, no controllers) so
/// the chat history can hot-reload them as plain Flutter widgets and the
/// widget tests can pump them directly.
Widget? renderToolOutput(
  BuildContext context,
  String toolName,
  Object? output,
) {
  if (output == null) return null;
  try {
    return switch (toolName) {
      'get_holdings' => _HoldingsTable(output: output),
      'list_payment_accounts' => _PaymentAccountsView(output: output),
      'compute_xirr' => _XirrSummary(output: output),
      'compute_net_worth' ||
      'get_net_worth_summary' => _NetWorthSparkline(output: output),
      'get_industry_breakdown' ||
      'get_geo_breakdown' ||
      'get_market_cap_breakdown' => _BreakdownView(output: output),
      'get_risk_alerts' => _RiskAlertList(output: output),
      // Analytical / Snapshot read-model renderers.
      'get_asset_allocation' => AssetAllocationView(output: output),
      'get_recurring_patterns' => RecurringPatternsView(output: output),
      'get_subscription_changes' => SubscriptionChangesView(output: output),
      'get_refund_links' => RefundLinksView(output: output),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Shared parsing helpers — backend numbers may arrive as int, double or
// string depending on the JSON encoder, so coerce defensively.
// ---------------------------------------------------------------------------

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String? _asString(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

DateTime? _asDate(Object? v) {
  if (v is! String) return null;
  return DateTime.tryParse(v);
}

Map<String, Object?>? _asMap(Object? v) {
  if (v is Map) {
    return v.map((k, value) => MapEntry(k.toString(), value));
  }
  return null;
}

List<Object?>? _asList(Object? v) {
  if (v is List) return List<Object?>.from(v);
  return null;
}

String _displayDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d.toLocal());

// ---------------------------------------------------------------------------
// Shared empty placeholder.
// ---------------------------------------------------------------------------

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.message, this.positive = false});
  final String message;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        children: [
          Icon(
            positive ? FLucideIcons.circleCheck : FLucideIcons.inbox,
            size: AppIconSizes.sm,
            color: context.theme.colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(message, style: context.captionStyle),
        ],
      ),
    );
  }
}

/// Whether the renderer for [toolName] would normally render the entire
/// payload inline. Callers can use this to decide whether to keep raw JSON
/// hidden behind a "查看 raw JSON" toggle even when the payload itself is
/// huge.
bool isOversizedToolPayload(String toolName, Object? output) {
  final m = _asMap(output);
  if (m == null) return false;
  switch (toolName) {
    case 'get_holdings':
      final holdings = _asMap(m['holdings']);
      return (holdings?.length ?? 0) > _kRawListLimit;
    case 'compute_net_worth':
      final list = _asList(m['series']);
      return (list?.length ?? 0) > _kRawListLimit;
    case 'get_risk_alerts':
      final list = _asList(m['alerts']);
      return (list?.length ?? 0) > _kRawListLimit;
    default:
      return false;
  }
}
