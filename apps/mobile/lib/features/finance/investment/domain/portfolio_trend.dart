import 'package:decimal/decimal.dart';

enum PortfolioTrendRange { month, quarter, yearToDate, year, all }

enum PortfolioTrendMetric { marketValue, performance }

enum PortfolioTrendQuality { complete, estimated }

class PortfolioTrendRequest {
  const PortfolioTrendRequest({required this.portfolioId, required this.range});

  final String portfolioId;
  final PortfolioTrendRange range;

  @override
  bool operator ==(Object other) =>
      other is PortfolioTrendRequest &&
      other.portfolioId == portfolioId &&
      other.range == range;

  @override
  int get hashCode => Object.hash(portfolioId, range);
}

class PortfolioTrendPoint {
  const PortfolioTrendPoint({
    required this.asOf,
    required this.marketValueInBase,
    required this.costBasisInBase,
    required this.cashValueInBase,
    required this.netFlowInBase,
    required this.performanceRatio,
    required this.quality,
  });

  final DateTime asOf;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal cashValueInBase;
  final Decimal netFlowInBase;

  /// Cash-flow-adjusted cumulative change from the first funded sample.
  final double performanceRatio;
  final PortfolioTrendQuality quality;
}

class PortfolioTrendSeries {
  const PortfolioTrendSeries({
    required this.portfolioId,
    required this.baseCurrency,
    required this.range,
    required this.points,
  });

  final String portfolioId;
  final String baseCurrency;
  final PortfolioTrendRange range;
  final List<PortfolioTrendPoint> points;

  PortfolioTrendPoint? get latest => points.lastOrNull;

  Decimal get currentValue => latest?.marketValueInBase ?? Decimal.zero;

  Decimal get periodValueChange {
    if (points.length < 2) return Decimal.zero;
    return points.last.marketValueInBase - points.first.marketValueInBase;
  }

  Decimal get periodNetFlow =>
      points.fold(Decimal.zero, (sum, point) => sum + point.netFlowInBase);

  double? get periodPerformanceRatio {
    if (points.length < 2 ||
        points.every((point) => point.marketValueInBase == Decimal.zero)) {
      return null;
    }
    return points.last.performanceRatio;
  }

  bool get hasEstimatedPoints =>
      points.any((point) => point.quality == PortfolioTrendQuality.estimated);
}
