import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/agents/agent.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth_providers;
import '../../../core/notifications/providers.dart' as notif_providers;
import '../../../design_system/design_system.dart';
import '../../health/agents/providers.dart' as health_agent_providers;
import '../../health/data/health_sync_service.dart';
import '../../health/data/morning_briefing_preferences.dart';
import '../../health/data/providers.dart' as health_data;
import 'inline_setting_row.dart';

/// `/settings/domains` — the LifeOS domain console.
///
/// Pulled out of the Settings overview (2026-05-29) so the overview stops
/// growing/shrinking as domains toggle on, and so per-domain operations
/// (HealthOS sync / briefing) have a focused home instead of crowding the
/// global preferences list. The overview now links here with a single
/// row. FinanceOS is the always-on seed domain; HealthOS / KnowledgeOS are
/// per-user opt-ins (D-1.5) — enabling one activates its AI tools + Memory
/// indexing + IA shell entry.
class DomainsSettingsPage extends ConsumerWidget {
  const DomainsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIns = ref.watch(auth_providers.domainOptInsProvider).value;
    final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
    final knowledgeEnabled = optIns?.contains(DomainScope.knowledge) ?? false;
    final colors = context.theme.colors;

    return FScaffold(
      header: FHeader.nested(
        title: const Text('LifeOS 域'),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s16,
          AppSpacing.s16,
          AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.s12),
            child: Text(
              '每个域独立开关。打开后该域的 AI 工具、Memory 索引与导航入口会启用。',
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                InlineLinkRow(
                  icon: FLucideIcons.wallet,
                  label: 'FinanceOS',
                  subtitle: '永远启用 (seed 域)',
                  trailingBadge: '已启用',
                  onTap: () {},
                ),
                _RowDivider(),
                InlineSwitchRow(
                  icon: FLucideIcons.heartPulse,
                  label: 'HealthOS',
                  subtitle: healthEnabled
                      ? '预览中 — AI 工具 + Memory 索引已启用'
                      : '预览版 — 打开后 AI 工具 + Memory 索引会启用',
                  value: healthEnabled,
                  onChanged: (v) {
                    ref
                        .read(auth_providers.domainOptInsProvider.notifier)
                        .setEnabled(DomainScope.health, v);
                  },
                ),
                if (healthEnabled) ...[
                  _RowDivider(),
                  InlineLinkRow(
                    icon: FLucideIcons.eye,
                    label: 'HealthOS · Today',
                    subtitle: '查看每日 Morning Briefing 卡片',
                    onTap: () => context.goNamed(AppRouteNames.healthToday),
                  ),
                  _RowDivider(),
                  const _HealthPlatformSyncRow(),
                  _RowDivider(),
                  const _MorningBriefingRunRow(),
                  _RowDivider(),
                  const _MorningBriefingHourRow(),
                ],
                _RowDivider(),
                InlineSwitchRow(
                  icon: FLucideIcons.brain,
                  label: 'KnowledgeOS',
                  subtitle: knowledgeEnabled
                      ? '预览中 — Inbox/Library/Review + AI tools + Memory 索引已启用'
                      : '预览版 — 个人决策与认知演化记忆库 (Decision Log / Recall / Review)',
                  value: knowledgeEnabled,
                  onChanged: (v) {
                    ref
                        .read(auth_providers.domainOptInsProvider.notifier)
                        .setEnabled(DomainScope.knowledge, v);
                  },
                ),
                if (knowledgeEnabled) ...[
                  _RowDivider(),
                  InlineLinkRow(
                    icon: FLucideIcons.inbox,
                    label: 'KnowledgeOS · Inbox',
                    subtitle: '捕获笔记 / 写决策 / 查看 Library 与 Review',
                    onTap: () => context.goNamed(AppRouteNames.knowledgeInbox),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-pixel ribbon divider between rows in a [SoftCard], matching the
/// settings-overview look (alpha 0.05, 14px horizontal inset).
class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 1,
        color: context.theme.colors.foreground.withValues(alpha: 0.05),
      ),
    );
  }
}

/// D-2.2 — manual "Sync from HealthKit / Health Connect" trigger.
///
/// Tapping requests permissions on first use, then pulls the last 30 days
/// into `health_metrics`. Background fetch / WorkManager scheduling lands
/// in D-2.5b; this is the dogfood path until then.
class _HealthPlatformSyncRow extends ConsumerStatefulWidget {
  const _HealthPlatformSyncRow();

  @override
  ConsumerState<_HealthPlatformSyncRow> createState() =>
      _HealthPlatformSyncRowState();
}

class _HealthPlatformSyncRowState
    extends ConsumerState<_HealthPlatformSyncRow> {
  bool _running = false;
  HealthSyncResult? _lastResult;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final service = await ref.read(
        health_data.healthSyncServiceProvider.future,
      );
      // Permissions are a precondition — request them if missing so the
      // user doesn't have to remember to do a separate "Connect" step.
      if (!await service.hasPermissions()) {
        final granted = await service.requestPermissions();
        if (!granted) {
          setState(() {
            _lastResult = HealthSyncResult.skipped(
              startedAt: DateTime.now().toUtc(),
              errorMessage: '权限被拒绝 — 在系统 Health 设置里再试',
            );
          });
          return;
        }
      }
      final result = await service.syncRange();
      setState(() => _lastResult = result);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _subtitle() {
    final r = _lastResult;
    if (_running) return '正在拉取…';
    if (r == null) return '从 HealthKit / Health Connect 拉取最近 30 天数据';
    if (!r.ok) return r.errorMessage ?? '上次同步失败';
    return '上次同步: ${r.upserted} 新写入 / ${r.unchanged} 未变 · 拉取 ${r.totalFetched} 项';
  }

  @override
  Widget build(BuildContext context) {
    return InlineLinkRow(
      icon: FLucideIcons.refreshCcw,
      label: 'Sync from HealthKit / Health Connect',
      subtitle: _subtitle(),
      onTap: _running ? () {} : _run,
    );
  }
}

/// D-2.5b — manual "Run morning briefing now" trigger + notification
/// permission status.
///
/// The user usually doesn't need to tap this — the workmanager background
/// task fires the agent daily and posts a local notification. The button
/// exists for dogfood + first-run flows (permission grant, sanity check).
class _MorningBriefingRunRow extends ConsumerStatefulWidget {
  const _MorningBriefingRunRow();

  @override
  ConsumerState<_MorningBriefingRunRow> createState() =>
      _MorningBriefingRunRowState();
}

class _MorningBriefingRunRowState
    extends ConsumerState<_MorningBriefingRunRow> {
  bool _running = false;
  AgentRunResult? _lastResult;
  String? _errorMessage;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _errorMessage = null;
    });
    try {
      // First-time runs need notification permission so the toast ever
      // actually reaches the user; request it before kicking off the agent
      // so the prompt and the run are paired.
      final notifier = ref.read(notif_providers.notificationServiceProvider);
      if (await notifier.isAvailable() && !await notifier.hasPermissions()) {
        await notifier.requestPermissions();
      }
      // `refresh` re-runs the autoDispose provider even if it was already in
      // the cache from an earlier invocation. We await the future directly
      // so the result lands in our local state.
      final result = await ref.refresh(
        health_agent_providers.manualMorningBriefingRunProvider.future,
      );
      setState(() => _lastResult = result);
    } on Object catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _subtitle() {
    if (_running) return '正在运行 Morning Briefing…';
    final err = _errorMessage;
    if (err != null) return 'Briefing failed: $err';
    final r = _lastResult;
    if (r == null) {
      return '后台每日 07:00 自动跑;点这里手动触发并发通知';
    }
    return switch (r.status) {
      AgentRunStatus.completed => 'Last run: ${r.summary ?? "completed"}',
      AgentRunStatus.skipped => 'Last run skipped: ${r.summary ?? "no signal"}',
      AgentRunStatus.failed => 'Last run failed: ${r.error ?? "unknown"}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return InlineLinkRow(
      icon: FLucideIcons.sunrise,
      label: 'Run Morning Briefing now',
      subtitle: _subtitle(),
      onTap: _running ? () {} : _run,
    );
  }
}

/// D-2.5b follow-up — user-configurable preferred local hour for the daily
/// briefing. Defaults to 07:00. Background workmanager fires at OS
/// discretion (≈24h period) so the hour is honoured strictly only by
/// in-process scheduling; the value is still surfaced through the
/// `AgentSchedule` so the briefing's documented intent matches the user's
/// preference.
class _MorningBriefingHourRow extends ConsumerWidget {
  const _MorningBriefingHourRow();

  Future<void> _pick(BuildContext context, WidgetRef ref, int current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current, minute: 0),
      helpText: 'Morning Briefing 时间',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    await ref.read(morningBriefingHourProvider.notifier).set(picked.hour);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = ref.watch(morningBriefingHourProvider);
    final label = hour.toString().padLeft(2, '0');
    return InlineLinkRow(
      icon: FLucideIcons.clock,
      label: 'Briefing 时间',
      subtitle: '每日大约 $label:00 触发 (后台调度窗口浮动)',
      trailingValue: '$label:00',
      onTap: () => _pick(context, ref, hour),
    );
  }
}
