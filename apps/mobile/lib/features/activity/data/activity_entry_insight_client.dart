/// Feature-owned seam for generating one-line activity entry insights.
///
/// The feature owns request shaping, deterministic fallback, and prompt text.
/// App bootstrap may inject an FRB-backed [ActivityEntryInsightClient], but the
/// Activity feature does not import app-level runtime providers directly.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../finance/data/domain/account.dart';
import '../../finance/data/domain/entry_kind.dart';
import '../../finance/data/domain/posting.dart';
import '../../finance/data/repositories/journal_entry_repository.dart';
import '../../finance/shared/entry_kind_labels.dart';

abstract class ActivityEntryInsightClient {
  Future<String?> explain(
    ActivityEntryInsightRequest request,
    AppLocalizations l10n,
  );
}

final activityEntryInsightClientProvider =
    Provider<ActivityEntryInsightClient?>((ref) => null);

final aiExplainEntryProvider = FutureProvider.autoDispose
    .family<String?, ActivityEntryInsightRequest>((ref, request) async {
      final l10n = lookupAppLocalizations(
        request.locale.languageCode == 'zh'
            ? const Locale('zh')
            : const Locale('en'),
      );
      final fallback = heuristicActivityEntryInsight(request.entry, l10n);
      final client = ref.watch(activityEntryInsightClientProvider);
      if (client == null) return fallback;

      try {
        final text = await client
            .explain(request, l10n)
            .timeout(const Duration(seconds: 15));
        return cleanActivityEntryAiInsight(text) ?? fallback;
      } on Object {
        return fallback;
      }
    });

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

String? heuristicActivityEntryInsight(
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

String activityEntryInsightSystem(Locale locale) {
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

String activityEntryInsightPrompt(
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
          '${p.units} ${activityEntryInsightDisplayUnit(p.unit)}',
  ];
  return lines.join('\n');
}

String _promptAccountLabel(Posting posting, Map<String, Account> accountsById) {
  final account = accountsById[posting.accountId];
  if (account == null) return posting.accountId;
  final side = account.category.name;
  return side.isEmpty ? account.name : '${account.name} ($side)';
}

String? cleanActivityEntryAiInsight(String? text) {
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

String activityEntryInsightDisplayUnit(String unit) {
  final colon = unit.indexOf(':');
  return colon >= 0 ? unit.substring(colon + 1) : unit;
}
