import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../accounts/ui/account_detail_page.dart';
import 'asset_type_labels.dart';

class ManualAssetDetailPage extends ConsumerWidget {
  const ManualAssetDetailPage({
    super.key,
    required this.asset,
    required this.repository,
  });

  final Asset asset;
  final ManualAssetRepository repository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ManualAssetMetadata.decode(asset.metadataJson);
    if (metadata is CashMetadata) {
      return AccountDetailPage(accountId: metadata.accountId);
    }

    final l10n = AppLocalizations.of(context);
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final linkedAccount = metadata == null
        ? null
        : accounts.where((item) => item.id == metadata.accountId).firstOrNull;
    return ObjectDetailScaffold(
      title: asset.name ?? asset.symbol,
      actions: [
        FHeaderAction(
          icon: FTooltip(
            tipBuilder: (_, _) => Text(l10n.manualAssetDetailEditAction),
            child: const Icon(FLucideIcons.pencil),
          ),
          semanticsLabel: l10n.manualAssetDetailEditAction,
          onPress: () => context.push(FinanceRoutes.wealthAssetEdit(asset.id)),
        ),
      ],
      childPad: false,
      child: FutureBuilder(
        future: repository.latestValuation(asset.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AssetDetailSkeleton();
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            children: [
              SoftCard(
                level: SoftCardLevel.hero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.manualAssetDetailCurrentValue,
                        style: context.captionStyle,
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      snapshot.data == null
                          ? Text('—', style: TypographyTokens.displayMedium)
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: AnimatedMoneyText(
                                amount: snapshot.data!.toDouble(),
                                currencyCode: asset.currency,
                                style: TypographyTokens.displayMedium,
                              ),
                            ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        manualAssetTypeLabel(l10n, asset.type),
                        style: context.bodyCaptionStyle,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              _ManualAssetFacts(
                asset: asset,
                metadata: metadata,
                linkedAccount: linkedAccount,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ManualAssetFacts extends ConsumerWidget {
  const _ManualAssetFacts({
    required this.asset,
    required this.metadata,
    required this.linkedAccount,
  });

  final Asset asset;
  final ManualAssetMetadata? metadata;
  final Account? linkedAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final rows = <({String label, String value})>[
      (
        label: l10n.accountDetailCurrencyLabel,
        value: asset.currency.toUpperCase(),
      ),
      if (metadata case final DepositMetadata deposit) ...[
        (
          label: l10n.manualAssetDetailPrincipal,
          value: formatters.currency(deposit.principal, code: asset.currency),
        ),
        (
          label: l10n.manualAssetDetailAnnualRate,
          value: formatters.percent(deposit.interestRate.toDouble()),
        ),
        if (deposit.startDate != null)
          (
            label: l10n.manualAssetDetailStartDate,
            value: formatters.date(deposit.startDate!),
          ),
        if (deposit.maturityDate != null)
          (
            label: l10n.manualAssetDetailMaturityDate,
            value: formatters.date(deposit.maturityDate!),
          ),
      ],
      if (metadata case final WealthProductMetadata product) ...[
        (
          label: l10n.manualAssetDetailPrincipal,
          value: formatters.currency(product.principal, code: asset.currency),
        ),
        (
          label: l10n.manualAssetDetailExpectedReturn,
          value: formatters.percent(product.expectedAnnualReturn.toDouble()),
        ),
        if (product.issuer != null && product.issuer!.isNotEmpty)
          (label: l10n.manualAssetDetailIssuer, value: product.issuer!),
        if (product.productCode != null && product.productCode!.isNotEmpty)
          (
            label: l10n.manualAssetDetailProductCode,
            value: product.productCode!,
          ),
        if (product.startDate != null)
          (
            label: l10n.manualAssetDetailStartDate,
            value: formatters.date(product.startDate!),
          ),
        if (product.maturityDate != null)
          (
            label: l10n.manualAssetDetailMaturityDate,
            value: formatters.date(product.maturityDate!),
          ),
      ],
    ];
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          children: [
            if (linkedAccount != null) ...[
              FTappable(
                onPress: () => context.push(
                  FinanceRoutes.wealthAccount(linkedAccount!.id),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.manualAssetDetailAccount,
                          style: context.captionStyle,
                        ),
                      ),
                      Text(
                        linkedAccount!.name,
                        style: context.bodyCaptionStyle,
                      ),
                      const SizedBox(width: AppSpacing.s4),
                      const Icon(
                        FLucideIcons.chevronRight,
                        size: AppIconSizes.sm,
                      ),
                    ],
                  ),
                ),
              ),
              const FDivider(),
            ],
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(row.label, style: context.captionStyle),
                    ),
                    const SizedBox(width: AppSpacing.s16),
                    Flexible(
                      child: Text(
                        row.value,
                        style: context.bodyCaptionStyle,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
