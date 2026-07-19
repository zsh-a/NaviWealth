import 'package:flutter/widgets.dart';

import '../../../../core/forms/forms.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

class LiabilityPaymentSheet extends StatefulWidget {
  const LiabilityPaymentSheet({
    super.key,
    required this.periodIndex,
    required this.amount,
    required this.today,
  });

  final int periodIndex;
  final String amount;
  final DateTime today;

  static Future<DateTime?> show(
    BuildContext context, {
    required int periodIndex,
    required String amount,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final calendarToday = DateTime(now.year, now.month, now.day);
    return showAppFormSheet<DateTime>(
      context: context,
      maxHeightFactor: 0.72,
      builder: (_) => LiabilityPaymentSheet(
        periodIndex: periodIndex,
        amount: amount,
        today: calendarToday,
      ),
    );
  }

  @override
  State<LiabilityPaymentSheet> createState() => _LiabilityPaymentSheetState();
}

class _LiabilityPaymentSheetState extends State<LiabilityPaymentSheet> {
  late DateTime _paymentDate;

  @override
  void initState() {
    super.initState();
    _paymentDate = widget.today;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.liabilityPaymentSheetTitle(widget.periodIndex),
      footer: AppSheetFooter(
        submitKey: const Key('liability-payment-submit'),
        submitLabel: l10n.liabilityPaymentSheetSubmit,
        cancelLabel: l10n.commonCancel,
        onSubmit: () => Navigator.of(context).pop(_paymentDate),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppStatusBanner(
            kind: AppStatusKind.info,
            message: l10n.liabilityPaymentSheetAmount(widget.amount),
            compact: true,
          ),
          const SizedBox(height: AppSpacing.s16),
          DateField(
            key: const Key('liability-payment-date'),
            label: l10n.liabilityPaymentSheetDate,
            initialValue: _paymentDate,
            firstDate: DateTime(1970),
            lastDate: widget.today,
            required: true,
            helperText: l10n.liabilityPaymentSheetDateHint,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _paymentDate = value);
            },
          ),
        ],
      ),
    );
  }
}
