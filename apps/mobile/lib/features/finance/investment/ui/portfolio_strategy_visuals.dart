import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../domain/strategy/portfolio_strategy.dart';
import '../domain/strategy/portfolio_strategy_template.dart';

PortfolioStrategyTemplate? strategyTemplateForKind(
  Iterable<PortfolioStrategyTemplate> templates,
  PortfolioStrategyKind kind,
) {
  for (final template in templates) {
    if (template.kind == kind) return template;
  }
  return null;
}

String strategyTemplateLabel(
  PortfolioStrategyTemplate template,
  Locale locale,
) => template.displayName(locale.languageCode);

IconData strategyTemplateIcon(PortfolioStrategyTemplate? template) {
  return switch (template?.iconToken) {
    'chart' => FLucideIcons.chartNoAxesCombined,
    'income' => FLucideIcons.handCoins,
    'shield' => FLucideIcons.shieldCheck,
    'target' => FLucideIcons.target,
    'sparkles' => FLucideIcons.sparkles,
    _ => FLucideIcons.layers,
  };
}
