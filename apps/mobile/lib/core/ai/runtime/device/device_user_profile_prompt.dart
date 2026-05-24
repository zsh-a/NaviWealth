/// Render a [ContextPack] into a short system-prompt appendix that grounds
/// the model in the user's actual finance posture (MT-2.5.M1.2,
/// `docs/roadmap-midterm-execution.md`).
///
/// The appendix is rendered in Chinese to match
/// [kDeviceSystemPrompt]'s register and keeps to a tight byte budget:
/// the model already pays for the static prompt + tool schemas, so every
/// additional byte here is felt on the first turn.
///
/// **Hard cap**: 1 KB serialised. The renderer truncates / drops fields
/// before going over, returning a partial appendix rather than letting
/// prompts inflate silently.
library;

import '../../contracts/base_context.dart';
import '../../contracts/context_pack.dart';

/// Maximum length in bytes for the rendered appendix (UTF-8). Mirrors
/// MT-2.5.M1.3's "8KB hard cap" budget but for the *appendix only* —
/// the full system prompt + clock + appendix stays well under 16KB.
const int kUserProfileAppendixByteCap = 1024;

/// Render `pack` into a system-prompt appendix, or `null` when the
/// pack has nothing usefully grounding to add. Always returns text
/// that starts with a single leading `\n\n` so callers can concatenate
/// it directly onto the base prompt.
String? renderContextPackSystemAppendix(ContextPack? pack) {
  if (pack == null) return null;
  final lines = <String>[];

  // Header — one line so the model can locate the block in the prompt.
  lines.add('用户画像（自动生成，仅供参考）：');

  final base = pack.base;
  final risk = _riskLabel(base.riskPreference);
  if (risk != null) {
    lines.add('- 风险偏好：$risk');
  }

  final currency = base.preferredCurrency.trim();
  if (currency.isNotEmpty) {
    lines.add('- 报表币种：$currency');
  }

  final accounts = base.accounts.totalCount;
  if (accounts > 0) {
    lines.add('- 账户数：$accounts');
  }

  final cf = base.cashflow;
  if (cf.monthsCovered > 0) {
    final months = cf.monthsCovered;
    final inflow = _minorToCompact(cf.averageInflowMinor);
    final outflow = _minorToCompact(cf.averageOutflowMinor);
    if (inflow != null && outflow != null) {
      lines.add(
        '- 近 $months 个月月均收入 $inflow ${cf.baseCurrency}，'
        '月均支出 $outflow ${cf.baseCurrency}（${_trendLabel(cf.trend)}）',
      );
    }
  }

  final fire = base.fireGoal;
  if (fire != null) {
    final progress = (fire.progressFraction * 100).clamp(0.0, 999.0);
    final progressStr = progress.toStringAsFixed(1);
    final eta = fire.yearsRemainingEstimate;
    final etaStr = eta == null ? '' : '，预计 ${eta.toStringAsFixed(1)} 年达成';
    lines.add('- FIRE 进度 $progressStr%$etaStr');
  }

  if (lines.length == 1) return null; // Header only — nothing to say.

  // Cap: drop trailing lines until we fit. The header always survives so
  // the model still knows a profile block was attempted.
  while (lines.length > 1 && _utf8ByteCount(lines.join('\n')) > kUserProfileAppendixByteCap) {
    lines.removeLast();
  }
  if (lines.length == 1) return null;

  return '\n\n${lines.join('\n')}';
}

String? _riskLabel(RiskPreference pref) => switch (pref) {
      RiskPreference.conservative => '保守（避免波动，优先保本）',
      RiskPreference.moderate => '中性（接受适度波动以换取长期回报）',
      RiskPreference.aggressive => '激进（接受较大回撤换取较高预期收益）',
    };

String _trendLabel(CashflowTrend trend) => switch (trend) {
      CashflowTrend.improving => '净流入改善',
      CashflowTrend.worsening => '净流入恶化',
      CashflowTrend.stable => '趋势平稳',
      CashflowTrend.unknown => '趋势未知',
    };

/// Minor-unit string → human-readable major unit. Returns `null` on parse
/// failure or non-positive amounts so the appendix simply omits the line.
String? _minorToCompact(String minor) {
  final n = int.tryParse(minor);
  if (n == null || n <= 0) return null;
  final major = n / 100.0;
  if (major >= 100000) {
    return '${(major / 10000).toStringAsFixed(1)} 万';
  }
  if (major >= 10000) {
    return '${(major / 10000).toStringAsFixed(2)} 万';
  }
  return major.toStringAsFixed(0);
}

int _utf8ByteCount(String s) {
  var count = 0;
  for (final rune in s.runes) {
    if (rune < 0x80) {
      count += 1;
    } else if (rune < 0x800) {
      count += 2;
    } else if (rune < 0x10000) {
      count += 3;
    } else {
      count += 4;
    }
  }
  return count;
}
