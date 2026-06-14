/// Garmin Connect account binding sheet.
///
/// Modal form for email/password login with MFA support.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../data/garmin/garmin_sync_controller.dart';
import '../data/providers.dart' as health_data;

/// Show the Garmin account binding sheet.
Future<void> showGarminAccountBindSheet({required BuildContext context}) {
  return showAppFormSheet<void>(
    context: context,
    builder: (context) => const _GarminAccountBindSheet(),
  );
}

class _GarminAccountBindSheet extends ConsumerStatefulWidget {
  const _GarminAccountBindSheet();

  @override
  ConsumerState<_GarminAccountBindSheet> createState() =>
      _GarminAccountBindSheetState();
}

class _GarminAccountBindSheetState
    extends ConsumerState<_GarminAccountBindSheet> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _mfaCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _mfaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(health_data.garminSyncControllerProvider);
    final region = ref.watch(health_data.garminRegionProvider);

    return AppSheet(
      title: state is GarminPendingMfa ? 'MFA Verification' : 'Connect Garmin',
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // MFA or credentials form
            if (state is GarminPendingMfa) ...[
              FTextFormField(
                control: FTextFieldControl.managed(controller: _mfaCtrl),
                hint: '123456',
                label: const Text('MFA Code'),
              ),
              const SizedBox(height: AppSpacing.s16),
              FButton(onPress: _submitMfa, child: const Text('Verify')),
            ] else ...[
              _GarminRegionPicker(
                selected: region,
                onChanged: (value) => ref
                    .read(health_data.garminRegionProvider.notifier)
                    .set(value),
              ),
              const SizedBox(height: AppSpacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(controller: _emailCtrl),
                hint: 'you@example.com',
                label: const Text('Email'),
              ),
              const SizedBox(height: AppSpacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(controller: _passwordCtrl),
                label: const Text('Password'),
                obscureText: true,
              ),
              const SizedBox(height: AppSpacing.s16),
              FButton(onPress: _connect, child: const Text('Connect')),
            ],

            // Error message
            if (state is GarminError) ...[
              const SizedBox(height: AppSpacing.s12),
              Text(
                state.message,
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.destructive,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Loading indicator
            if (state is GarminSyncing) ...[
              const SizedBox(height: AppSpacing.s16),
              const Center(child: FProgress()),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) return;
    await ref
        .read(health_data.garminSyncControllerProvider.notifier)
        .connect(email, password);
  }

  Future<void> _submitMfa() async {
    final code = _mfaCtrl.text.trim();
    if (code.isEmpty) return;
    await ref
        .read(health_data.garminSyncControllerProvider.notifier)
        .submitMfa(code);
  }
}

class _GarminRegionPicker extends StatelessWidget {
  const _GarminRegionPicker({required this.selected, required this.onChanged});

  final health_data.GarminRegion selected;
  final ValueChanged<health_data.GarminRegion> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Region',
          style: typography.xs.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.s6),
        Row(
          children: [
            for (final region in health_data.GarminRegion.values) ...[
              if (region != health_data.GarminRegion.values.first)
                const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: FButton(
                  variant: selected == region
                      ? FButtonVariant.primary
                      : FButtonVariant.outline,
                  onPress: () => onChanged(region),
                  child: Text(region.label),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(selected.description, style: context.captionStyle),
      ],
    );
  }
}
