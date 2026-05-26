/// Placeholder UI for the HealthOS tabs (`docs/healthos-domain.md`
/// §5, D-2.3).
///
/// D-2.3 lands the IA dock + opt-in plumbing, but the Today / Trend /
/// Plan surfaces will only have real content once D-2.2 (HealthKit /
/// Health Connect adapter) populates the `health_metrics` table. Until
/// then the user lands on this stub page, which is also a useful
/// "preview" surface during the Option B dock dogfood window
/// (`lifeos-shell.md` §3 decision gate).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';

/// Which Health tab is being rendered. Drives the headline + subtitle
/// copy; the body is the same "data lands in D-2.2" callout regardless.
enum HealthTab { today, trend, plan }

class HealthPlaceholderPage extends ConsumerWidget {
  const HealthPlaceholderPage({super.key, required this.tab});

  final HealthTab tab;

  String get _title => switch (tab) {
    HealthTab.today => 'Today · HealthOS',
    HealthTab.trend => 'Trend · HealthOS',
    HealthTab.plan => 'Plan · HealthOS',
  };

  String get _headline => switch (tab) {
    HealthTab.today => 'Today',
    HealthTab.trend => 'Trends',
    HealthTab.plan => 'Plan',
  };

  String get _subtitle => switch (tab) {
    HealthTab.today =>
      'Sleep / HRV / recovery — live signals will appear once data syncs in.',
    HealthTab.trend =>
      'Weekly and monthly trend charts arrive with the HealthKit / Health Connect adapter.',
    HealthTab.plan =>
      'Recovery + load suggestions land alongside the trend view.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.favorite_outline,
                size: 56,
                color: Colors.pink,
              ),
              const SizedBox(height: AppSpacing.s16),
              Text(
                _headline,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                _subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s16),
              Text(
                'HealthOS · preview build (D-2.3)\n'
                'Data adapters land in D-2.2.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
