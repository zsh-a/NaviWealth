/// Locale-aware [OpportunityExplanationTexts] backed by AppLocalizations.
///
/// Explanations are generated at scan time and cached verbatim (UI and AI
/// read the same strings), so they are produced in the user's active
/// locale. A rescan after a locale switch regenerates them.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/ai/agents/agent_l10n.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/services/opportunity_explanation_texts.dart';

final opportunityExplanationTextsProvider =
    Provider<OpportunityExplanationTexts>((ref) {
      final locale = supportedAgentLocale(
        ref.watch(localeProvider) ?? PlatformDispatcher.instance.locale,
      );
      return LocalizedOpportunityExplanationTexts(
        lookupAppLocalizations(locale),
        AppFormatters(locale: locale),
      );
    });

class LocalizedOpportunityExplanationTexts
    implements OpportunityExplanationTexts {
  const LocalizedOpportunityExplanationTexts(this._l10n, this._formatters);

  final AppLocalizations _l10n;
  final AppFormatters _formatters;

  @override
  String percent(Decimal ratio) =>
      _formatters.percent(ratio.toDouble(), decimalDigits: 1);

  @override
  String money(Money value) =>
      _formatters.currency(value.amount, code: value.currency);

  @override
  String yieldStrength(String yieldPct, String score) =>
      _l10n.optionsExplainYieldStrength(yieldPct, score);

  @override
  String liquidityStrength(String spread, int openInterest, String score) =>
      _l10n.optionsExplainLiquidityStrength(spread, openInterest, score);

  @override
  String safetyStrength(String margin, String score) =>
      _l10n.optionsExplainSafetyStrength(margin, score);

  @override
  String ivStrength(String iv, String score) =>
      _l10n.optionsExplainIvStrength(iv, score);

  @override
  String ivUnknown() => _l10n.optionsExplainIvUnknown;

  @override
  String fitStrength(String score) => _l10n.optionsExplainFitStrength(score);

  @override
  String eventStrength(String score) =>
      _l10n.optionsExplainEventStrength(score);

  @override
  String eventUnavailable() => _l10n.optionsExplainEventUnavailable;

  @override
  String genericScore(String dimension, String score) =>
      _l10n.optionsExplainGenericScore(dimension, score);

  @override
  String yieldWeak(String yieldPct, String score) =>
      _l10n.optionsExplainYieldWeak(yieldPct, score);

  @override
  String liquidityWeak(String spread, String score) =>
      _l10n.optionsExplainLiquidityWeak(spread, score);

  @override
  String safetyWeak(String margin, String score) =>
      _l10n.optionsExplainSafetyWeak(margin, score);

  @override
  String ivWeak(String score) => _l10n.optionsExplainIvWeak(score);

  @override
  String fitWeak(String score) => _l10n.optionsExplainFitWeak(score);

  @override
  String eventWeak(String score) => _l10n.optionsExplainEventWeak(score);

  @override
  String eventCheck() => _l10n.optionsExplainEventCheck;

  @override
  String summaryPut(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  ) => _l10n.optionsExplainSummaryPut(symbol, dte, strike, yieldPct, margin);

  @override
  String summaryCall(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  ) => _l10n.optionsExplainSummaryCall(symbol, dte, strike, yieldPct, margin);

  @override
  String bestForPutConservative() => _l10n.optionsExplainBestForPutConservative;

  @override
  String bestForPutBalanced() => _l10n.optionsExplainBestForPutBalanced;

  @override
  String bestForPutAggressive() => _l10n.optionsExplainBestForPutAggressive;

  @override
  String bestForCallConservative() =>
      _l10n.optionsExplainBestForCallConservative;

  @override
  String bestForCallBalanced() => _l10n.optionsExplainBestForCallBalanced;

  @override
  String bestForCallAggressive() => _l10n.optionsExplainBestForCallAggressive;

  @override
  String avoidPut() => _l10n.optionsExplainAvoidPut;

  @override
  String avoidCall() => _l10n.optionsExplainAvoidCall;

  @override
  String worstCasePut(
    String symbol,
    String strike,
    String breakeven,
    String cash,
  ) => _l10n.optionsExplainWorstPut(symbol, strike, breakeven, cash);

  @override
  String worstCaseCall(String symbol, String strike, String cap) =>
      _l10n.optionsExplainWorstCall(symbol, strike, cap);

  @override
  String leapsSummary(
    String symbol,
    int dte,
    String strike,
    String cost,
    String delta,
  ) => _l10n.optionsExplainLeapsSummary(symbol, dte, strike, cost, delta);

  @override
  String leapsWorstCase(String symbol, String strike, String cost) =>
      _l10n.optionsExplainLeapsWorstCase(symbol, strike, cost);

  @override
  String leapsBestFor() => _l10n.optionsExplainLeapsBestFor;

  @override
  String leapsAvoid() => _l10n.optionsExplainLeapsAvoid;

  @override
  String leapsCostBullet(String costPct) =>
      _l10n.optionsExplainLeapsCostBullet(costPct);

  @override
  String leapsLeverageBullet(String leverage, String delta) =>
      _l10n.optionsExplainLeapsLeverageBullet(leverage, delta);

  @override
  String leapsIntrinsicBullet(String intrinsicPct) =>
      _l10n.optionsExplainLeapsIntrinsicBullet(intrinsicPct);

  @override
  String leapsSpreadBullet(String spread) =>
      _l10n.optionsExplainLeapsSpreadBullet(spread);

  @override
  String leapsThetaBullet(String extrinsic) =>
      _l10n.optionsExplainLeapsThetaBullet(extrinsic);

  @override
  String leapsFundingBullet(String coverage) =>
      _l10n.optionsExplainLeapsFundingBullet(coverage);
}
