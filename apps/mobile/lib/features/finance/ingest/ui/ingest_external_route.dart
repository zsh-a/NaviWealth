import '../../composition/finance_route_paths.dart';
import '../domain/ingest_models.dart';
import '../domain/minor_unit_amount.dart';

String buildIngestTransferRoute(ParsedTransaction parsed) {
  return Uri(
    path: FinanceRoutes.transfer,
    queryParameters: <String, String>{
      'amount': formatAbsoluteMinorUnitAmount(parsed.amountMinor),
      'date': _localYmd(parsed.occurredAt),
      'note': parsed.description,
    },
  ).toString();
}

String buildIngestTradeRoute(ParsedTransaction parsed) {
  return Uri(
    path: FinanceRoutes.tradeEntry,
    queryParameters: <String, String>{
      if (parsed.activitySide != null) 'side': parsed.activitySide!,
      if (parsed.instrumentSymbol != null) 'symbol': parsed.instrumentSymbol!,
      if (parsed.quantity != null) 'quantity': parsed.quantity!,
      if (parsed.unitPrice != null) 'price': parsed.unitPrice!,
      'currency': parsed.currency,
      'date': _localYmd(parsed.occurredAt),
      'note': parsed.description,
      'ingest': '1',
    },
  ).toString();
}

String _localYmd(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
