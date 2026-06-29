import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/entry_kind.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/write/write.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../finance/data/repositories/journal_entry_providers.dart';
import '../../finance/data/repositories/providers.dart';
import '../../shared/account_l10n.dart';
import '../../shared/entry_kind_labels.dart';

/// Full-page detail surface for one journal entry. Pushed when the user
/// taps any row in the unified Activity timeline.
///
/// Layout (top → bottom):
///  1. Hero amount + title + date / time
///  2. Local insight block for deterministic transaction patterns
///  3. Posting breakdown (debits / credits in the existing widget)
///  4. (Future) tags, notes, edit / delete actions
class ActivityEntryDetailPage extends ConsumerWidget {
  const ActivityEntryDetailPage({
    super.key,
    required this.entry,
    required this.accountsById,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final aiInsight = ref
        .watch(
          aiExplainEntryProvider(
            ActivityEntryInsightRequest(
              entry: entry,
              accountsById: accountsById,
              locale: Localizations.localeOf(context),
            ),
          ),
        )
        .value;
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    return ObjectDetailScaffold(
      title: l10n.activityEntryDetailTitle,
      actions: [
        if (classification.kind == EntryKind.expense)
          FHeaderAction(
            icon: const Icon(FLucideIcons.pencil),
            onPress: () => context.go(AppRoutes.expense(entry.entry.id)),
          ),
      ],
      childPad: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s8,
          AppSpacing.s16,
          AppSpacing.s32,
        ),
        children: [
          // AiTouchMark: surfaces when this journal entry was created
          // by an accepted AI proposal. Self-gating: hidden otherwise.
          Align(
            alignment: Alignment.centerLeft,
            child: AiTouchMark(
              entityType: 'journal_entries',
              entityId: entry.entry.id,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          _HeroAmountCard(
            entry: entry,
            accountsById: accountsById,
            formatters: formatters,
          ),
          if (aiInsight != null) ...[
            const SizedBox(height: AppSpacing.s12),
            _AiInsightCard(insight: aiInsight),
          ],
          const SizedBox(height: AppSpacing.s12),
          _LedgerBreakdownCard(
            postings: entry.postings,
            accountsById: accountsById,
            formatters: formatters,
          ),
        ],
      ),
    );
  }
}

class ActivityEntryInsightRequest {
  ActivityEntryInsightRequest({
    required this.entry,
    required this.accountsById,
    required this.locale,
  }) : _postingSignature = _buildPostingSignature(entry),
       _accountSignature = _buildAccountSignature(entry, accountsById);

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final Locale locale;
  final String _postingSignature;
  final String _accountSignature;

  @override
  bool operator ==(Object other) {
    return other is ActivityEntryInsightRequest &&
        other.entry.entry.id == entry.entry.id &&
        other.entry.entry.date == entry.entry.date &&
        other.entry.entry.narration == entry.entry.narration &&
        other.entry.entry.payee == entry.entry.payee &&
        other.locale == locale &&
        other._postingSignature == _postingSignature &&
        other._accountSignature == _accountSignature;
  }

  @override
  int get hashCode => Object.hash(
    entry.entry.id,
    entry.entry.date,
    entry.entry.narration,
    entry.entry.payee,
    locale,
    _postingSignature,
    _accountSignature,
  );

  static String _buildPostingSignature(JournalEntryWithPostings entry) {
    return entry.postings
        .map((p) => '${p.id}:${p.accountId}:${p.units}:${p.unit}:${p.position}')
        .join('|');
  }

  static String _buildAccountSignature(
    JournalEntryWithPostings entry,
    Map<String, Account> accountsById,
  ) {
    return entry.postings
        .map((p) {
          final account = accountsById[p.accountId];
          return '${p.accountId}:${account?.name}:${account?.category.name}';
        })
        .join('|');
  }
}

final aiExplainEntryProvider = FutureProvider.autoDispose
    .family<String?, ActivityEntryInsightRequest>((ref, request) async {
      final l10n = lookupAppLocalizations(
        request.locale.languageCode == 'zh'
            ? const Locale('zh')
            : const Locale('en'),
      );
      final fallback = _heuristicInsight(request.entry, l10n);
      final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
      if (llmBridge == null) return fallback;

      try {
        final response = await llmBridge
            .completeProfile(
              messages: <Map<String, Object?>>[
                <String, Object?>{
                  'role': 'system',
                  'content': _activityInsightSystem(request.locale),
                },
                <String, Object?>{
                  'role': 'user',
                  'content': _activityInsightPrompt(request, l10n),
                },
              ],
              maxOutputTokens: 256,
              metadata: const <String, Object?>{
                'surface': 'finance_activity_insight',
                'agent_id': 'finance_activity_insight',
              },
            )
            .timeout(const Duration(seconds: 15));
        final body = response['content'];
        final text = _cleanAiInsight(body is String ? body : null);
        return text ?? fallback;
      } on Object {
        return fallback;
      }
    });

class ActivityEntryDetailArgs {
  const ActivityEntryDetailArgs({
    required this.entry,
    required this.accountsById,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
}

class ActivityEntryDetailRoute extends ConsumerWidget {
  const ActivityEntryDetailRoute({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(_activityEntryDetailProvider(entryId));
    return detailAsync.when(
      loading: () => AppPageScaffold(
        title: l10n.activityEntryDetailTitle,
        child: const Center(child: FCircularProgress()),
      ),
      error: (error, _) => AppPageScaffold(
        title: l10n.activityEntryDetailTitle,
        child: AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: '$error',
          action: FButton(
            variant: FButtonVariant.ghost,
            onPress: () =>
                ref.invalidate(_activityEntryDetailProvider(entryId)),
            child: Text(l10n.commonRetry),
          ),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return AppPageScaffold(
            title: l10n.activityEntryDetailTitle,
            child: AppEmptyState.error(
              title: l10n.routeNotFoundTitle,
              message: l10n.routeNotFoundMessage('/activity/entry/$entryId'),
            ),
          );
        }
        return ActivityEntryDetailPage(
          entry: detail.entry,
          accountsById: detail.accountsById,
        );
      },
    );
  }
}

final _activityEntryDetailProvider = FutureProvider.autoDispose
    .family<_ActivityEntryDetailData?, String>((ref, entryId) async {
      final repo = await ref.watch(journalEntryRepositoryProvider.future);
      final accounts = await ref.watch(allAccountsStreamProvider.future);
      final entry = await repo.getById(entryId);
      if (entry == null) return null;
      return _ActivityEntryDetailData(
        entry: entry,
        accountsById: {for (final account in accounts) account.id: account},
      );
    });

class _ActivityEntryDetailData {
  const _ActivityEntryDetailData({
    required this.entry,
    required this.accountsById,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
}

class _HeroAmountCard extends StatelessWidget {
  const _HeroAmountCard({
    required this.entry,
    required this.accountsById,
    required this.formatters,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final headline = _headlinePosting(entry.postings, accountsById);
    final dateLine = formatters.dateTime(entry.entry.date);
    final title = entry.entry.narration.isEmpty ? '—' : entry.entry.narration;
    final payee = entry.entry.payee;
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    final tint = _tintForKind(classification.kind, colors, semantic);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _KindGlyph(kind: classification.kind, tint: tint),
              const SizedBox(width: AppSpacing.s12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _KindLabel(
                    label: entryKindLabel(
                      AppLocalizations.of(context),
                      classification.kind,
                    ),
                    tint: tint,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Flexible(
                child: Text(
                  dateLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.captionStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (headline != null)
            SignedMoneyText(
              amount: headline.units,
              unit: headline.unit,
              formatters: formatters,
              style: TypographyTokens.numericDisplay.copyWith(height: 1.05),
            ),
          const SizedBox(height: AppSpacing.s12),
          Text(title, style: context.titleLabelStyle.copyWith(height: 1.22)),
          if (payee != null && payee.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(payee, style: context.bodyCaptionStyle.copyWith(height: 1.35)),
          ],
        ],
      ),
    );
  }
}

class _KindGlyph extends StatelessWidget {
  const _KindGlyph({required this.kind, required this.tint});

  final EntryKind kind;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: AppOpacity.light),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(_iconForKind(kind), color: tint, size: AppIconSizes.sm),
    );
  }
}

class _KindLabel extends StatelessWidget {
  const _KindLabel({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.microLabelStyle.copyWith(color: colors.foreground),
      ),
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({required this.insight});

  final String insight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              FLucideIcons.sparkles,
              size: AppIconSizes.xs,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.activityEntryDetailAiExplanation,
                  style: context.labelStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  insight,
                  style: context.bodyCaptionStyle.copyWith(height: 1.38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerBreakdownCard extends StatelessWidget {
  const _LedgerBreakdownCard({
    required this.postings,
    required this.accountsById,
    required this.formatters,
  });

  final List<Posting> postings;
  final Map<String, Account> accountsById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totals = _computeUnitTotals(postings);
    return SoftCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.activityEntryDetailLedgerTitle,
                  style: context.labelStyle,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppBadge(
                label: l10n.activityEntryDetailLegCount(postings.length),
                icon: FLucideIcons.gitBranch,
                size: AppBadgeSize.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          const AppDivider(horizontalPadding: 0),
          for (var i = 0; i < postings.length; i++) ...[
            if (i > 0) const AppDivider(horizontalPadding: 0),
            _DetailPostingRow(
              posting: postings[i],
              accountsById: accountsById,
              formatters: formatters,
            ),
          ],
          if (totals.isNotEmpty) ...[
            const AppDivider(horizontalPadding: 0),
            const SizedBox(height: AppSpacing.s12),
            for (final entry in totals.entries)
              _DetailUnitBalanceRow(
                unit: entry.key,
                total: entry.value,
                formatters: formatters,
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailPostingRow extends StatelessWidget {
  const _DetailPostingRow({
    required this.posting,
    required this.accountsById,
    required this.formatters,
  });

  final Posting posting;
  final Map<String, Account> accountsById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final account = accountsById[posting.accountId];
    final accountLabel = account == null
        ? posting.accountId
        : localizedAccountPath(
            l10n,
            account,
            accountsById,
            dropSystemRoot: false,
          );
    final cost = posting.cost;
    final price = posting.price;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  accountLabel,
                  style: context.mediumLabelStyle.copyWith(height: 1.35),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              SignedMoneyText(
                amount: posting.units,
                unit: _displayUnit(posting.unit),
                formatters: formatters,
                style: context.labelStyle,
              ),
            ],
          ),
          if (cost != null || price != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s4,
              children: [
                if (cost != null)
                  AppBadge(
                    label: _costLabel(cost),
                    icon: FLucideIcons.box,
                    size: AppBadgeSize.compact,
                  ),
                if (price != null)
                  AppBadge(
                    label: '@ ${_format(price.perUnit)} ${price.currency}',
                    icon: FLucideIcons.badgeCent,
                    size: AppBadgeSize.compact,
                  ),
              ],
            ),
          ],
          // account == null 时 accountLabel 已回退为 posting.accountId，
          // 无需额外兜底文本。数据库验证：当前无孤立 posting 数据。
        ],
      ),
    );
  }
}

class _DetailUnitBalanceRow extends StatelessWidget {
  const _DetailUnitBalanceRow({
    required this.unit,
    required this.total,
    required this.formatters,
  });

  final String unit;
  final Decimal total;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: Row(
        children: [
          Icon(
            FLucideIcons.circleAlert,
            size: AppIconSizes.xs,
            color: colors.destructive,
          ),
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(
              'Σ ${_displayUnit(unit)}',
              style: context.captionLabelStyle.copyWith(
                color: colors.destructive,
              ),
            ),
          ),
          SignedMoneyText(
            amount: total,
            unit: _displayUnit(unit),
            formatters: formatters,
            style: context.captionLabelStyle,
            color: colors.destructive,
          ),
        ],
      ),
    );
  }
}

String? _heuristicInsight(
  JournalEntryWithPostings entry,
  AppLocalizations l10n,
) {
  final text = [
    entry.entry.narration,
    if (entry.entry.payee != null) entry.entry.payee!,
  ].join(' ').toLowerCase();
  if (_containsAny(text, const [
    'netflix',
    'spotify',
    'prime',
    'subscription',
    '订阅',
    '会员',
    '自动续费',
    '续费',
    '月费',
  ])) {
    return l10n.activityEntryDetailInsightSubscription;
  }
  if (_containsAny(text, const [
    'rent',
    'mortgage',
    'housing',
    '房租',
    '租金',
    '房贷',
    '按揭',
    '物业',
  ])) {
    return l10n.activityEntryDetailInsightHousing;
  }
  if (_containsAny(text, const [
    'salary',
    'payroll',
    'wage',
    '工资',
    '薪资',
    '薪水',
    '发薪',
    '奖金',
  ])) {
    return l10n.activityEntryDetailInsightIncome;
  }
  if (_containsAny(text, const [
    'restaurant',
    'dining',
    'food',
    'lunch',
    'dinner',
    'breakfast',
    '外卖',
    '餐饮',
    '美团',
    '饿了么',
    '麦当劳',
    '肯德基',
    '星巴克',
  ])) {
    return l10n.activityEntryDetailInsightDining;
  }
  if (_containsAny(text, const [
    'uber',
    'lyft',
    'taxi',
    'transit',
    'metro',
    'subway',
    '滴滴',
    '打车',
    '地铁',
    '公交',
    '高铁',
    '火车',
    '机票',
    '航空',
  ])) {
    return l10n.activityEntryDetailInsightTransport;
  }
  if (_containsAny(text, const [
    'shopping',
    'mall',
    'store',
    'taobao',
    'jd.com',
    'pinduoduo',
    '淘宝',
    '京东',
    '拼多多',
    '天猫',
    '购物',
  ])) {
    return l10n.activityEntryDetailInsightShopping;
  }
  return null;
}

bool _containsAny(String text, List<String> keywords) {
  return keywords.any(text.contains);
}

String _activityInsightSystem(Locale locale) {
  final zh = locale.languageCode == 'zh';
  return zh
      ? '你是 NaviWealth 的本地财务分析助手。根据一笔复式记账记录，输出一句具体、克制的洞察。'
            '不要编造商户、类别、预算、频率或未来交易。不要输出 Markdown、项目符号或标题。'
            '如果信息不足，只解释这笔记录本身。'
      : 'You are NaviWealth local finance analysis. Explain one double-entry '
            'journal entry in one concise, specific sentence. Do not invent '
            'merchants, categories, budgets, recurrence, or future activity. '
            'Do not output Markdown, bullets, or a heading. If evidence is '
            'thin, explain only what this entry shows.';
}

String _activityInsightPrompt(
  ActivityEntryInsightRequest request,
  AppLocalizations l10n,
) {
  final entry = request.entry.entry;
  final classification = classifyEntryKind(
    postings: request.entry.postings,
    resolveCategory: (id) => request.accountsById[id]?.category,
  );
  final lines = [
    'kind: ${entryKindLabel(l10n, classification.kind)}',
    'date: ${entry.date.toUtc().toIso8601String()}',
    'narration: ${entry.narration}',
    if (entry.payee != null && entry.payee!.isNotEmpty) 'payee: ${entry.payee}',
    'postings:',
    for (final p in request.entry.postings)
      '- ${_promptAccountLabel(p, request.accountsById)}: '
          '${p.units} ${_displayUnit(p.unit)}',
  ];
  return lines.join('\n');
}

String _promptAccountLabel(Posting posting, Map<String, Account> accountsById) {
  final account = accountsById[posting.accountId];
  if (account == null) return posting.accountId;
  final side = account.category.name;
  return side.isEmpty ? account.name : '${account.name} ($side)';
}

String? _cleanAiInsight(String? text) {
  if (text == null) return null;
  var value = text
      .replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '')
      .replaceAll(RegExp(r'\s*```$'), '')
      .trim();
  value = value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join(' ');
  value = value.replaceFirst(RegExp(r'^[-*•]\s*'), '').trim();
  if (value.isEmpty) return null;
  const maxChars = 260;
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars).trimRight()}...';
}

Posting? _headlinePosting(
  List<Posting> postings,
  Map<String, Account> accounts,
) {
  Posting? headline;
  Decimal? best;
  Posting? fallback;
  Decimal? fallbackBest;
  for (final p in postings) {
    final magnitude = p.units.abs();
    if (fallbackBest == null || magnitude > fallbackBest) {
      fallbackBest = magnitude;
      fallback = p;
    }

    final account = accounts[p.accountId];
    if (account == null) continue;
    if (account.category != AccountSide.asset &&
        account.category != AccountSide.liability) {
      continue;
    }
    if (best == null || magnitude > best) {
      best = magnitude;
      headline = p;
    }
  }
  return headline ?? fallback;
}

IconData _iconForKind(EntryKind kind) {
  switch (kind) {
    case EntryKind.income:
      return FLucideIcons.arrowDownLeft;
    case EntryKind.expense:
      return FLucideIcons.shoppingBag;
    case EntryKind.payment:
      return FLucideIcons.banknote;
    case EntryKind.transfer:
      return FLucideIcons.arrowLeftRight;
    case EntryKind.trade:
      return FLucideIcons.chartLine;
    case EntryKind.adjustment:
      return FLucideIcons.slidersHorizontal;
    case EntryKind.opening:
      return FLucideIcons.flag;
    case EntryKind.other:
      return FLucideIcons.receipt;
  }
}

Color _tintForKind(EntryKind kind, FColors colors, SemanticColors semantic) {
  switch (kind) {
    case EntryKind.income:
    case EntryKind.trade:
      return colors.primary;
    case EntryKind.expense:
    case EntryKind.payment:
      return semantic.danger;
    case EntryKind.transfer:
      return semantic.info;
    case EntryKind.adjustment:
      return semantic.warning;
    case EntryKind.opening:
    case EntryKind.other:
      return colors.mutedForeground;
  }
}

String _costLabel(Cost cost) {
  final lot = cost.lotId;
  final base = '{${_format(cost.perUnit)} ${cost.currency}}';
  return lot == null ? base : '$base $lot';
}

String _format(Decimal value) {
  if (value == Decimal.zero) return '0';
  final text = value.toString();
  if (!text.contains('.')) return text;
  final trimmed = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}

/// Strip the `market:` prefix from an asset unit ID so the UI shows
/// `AAPL` instead of `usStock:AAPL`.
String _displayUnit(String unit) {
  final colon = unit.indexOf(':');
  return colon >= 0 ? unit.substring(colon + 1) : unit;
}

Map<String, Decimal> _computeUnitTotals(List<Posting> postings) {
  final totals = <String, Decimal>{};
  for (final posting in postings) {
    totals.update(
      posting.unit,
      (existing) => existing + posting.units,
      ifAbsent: () => posting.units,
    );
  }
  totals.removeWhere((_, value) => value == Decimal.zero);
  return totals;
}
