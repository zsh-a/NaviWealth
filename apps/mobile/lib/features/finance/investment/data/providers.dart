import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart' as dom;
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';

import '../application/trade_entry_submission_service.dart';
import '../domain/cost_basis/fifo_strategy.dart';
import '../domain/cost_basis_engine.dart';
import '../domain/fx_pnl/fx_pnl_breakdown.dart';
import '../domain/holding_price_source.dart';
import '../domain/holding_service.dart';
import '../domain/models/corporate_actions.dart';
import '../domain/models/holding_snapshot.dart';
import '../domain/models/lot.dart';
import '../domain/models/realized_pnl.dart';
import '../domain/models/trade_events.dart';
import '../domain/reporting/holding_report.dart';
import '../domain/returns/portfolio_return.dart';
import '../domain/trade_entry/default_trade_entry_service.dart';
import '../domain/trade_entry/trade_entry_service.dart';
import 'corporate_action_repository.dart';
import 'portfolio_return_service.dart';

part 'providers_corporate_actions.dart';
part 'providers_device_snapshot.dart';
part 'providers_holdings.dart';
part 'providers_market_inputs.dart';
part 'providers_reports.dart';
part 'providers_trade_entry.dart';
