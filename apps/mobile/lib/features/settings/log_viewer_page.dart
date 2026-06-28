import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:talker/talker.dart';

import '../../core/logging/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

/// Debug-only page that displays Talker's log history in real time.
class LogViewerPage extends ConsumerStatefulWidget {
  const LogViewerPage({super.key});

  @override
  ConsumerState<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends ConsumerState<LogViewerPage> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _copyAll(BuildContext context, Talker talker) async {
    final text = _serialize(talker);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    AppMessenger.show(
      context,
      ToastKind.info,
      AppLocalizations.of(context).settingsLogsCopiedToast,
    );
  }

  Future<void> _shareAll(Talker talker) async {
    final text = _serialize(talker);
    if (text.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'NaviWealth diagnostic logs'),
    );
  }

  Future<void> _clearAll(BuildContext context, Talker talker) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showConfirmDialog(
      context: context,
      title: Text(l10n.settingsLogsClearTitle),
      body: Text(l10n.settingsLogsClearBody),
      confirmLabel: l10n.settingsLogsClearAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (confirm != true) return;
    talker.cleanHistory();
    if (mounted) setState(() {});
  }

  /// Flatten the in-memory history to a copyable text block. Order
  /// matches what the user sees on screen.
  static String _serialize(Talker talker) {
    final buf = StringBuffer();
    for (final entry in talker.history) {
      buf.writeln(entry.generateTextMessage());
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final talker = ref.watch(talkerProvider);

    return AppPageScaffold(
      title: l10n.settingsLogsTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.copy),
          onPress: () => _copyAll(context, talker),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.share2),
          onPress: () => _shareAll(talker),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.trash2),
          onPress: () => _clearAll(context, talker),
        ),
      ],
      childPad: false,
      child: StreamBuilder<TalkerData>(
        stream: talker.stream,
        builder: (context, _) {
          final logs = talker.history;
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.s8),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _LogTile(log: log);
            },
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final TalkerData log;

  @override
  Widget build(BuildContext context) {
    final color = _colorForLevel(context, log.logLevel);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: SoftCard(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s6,
                    vertical: AppSpacing.s2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: AppOpacity.medium),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    log.title ?? log.logLevel?.name ?? 'log',
                    style: context.microLabelStyle.copyWith(color: color),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(log.displayTime(), style: context.microCaptionStyle),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(log.message ?? '', style: context.theme.typography.body.xs),
            if (log.error != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                '${log.error}',
                style: context.captionStyle.copyWith(
                  color: context.theme.colors.destructive,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _colorForLevel(BuildContext context, LogLevel? level) {
    final semantic = SemanticColors.of(context);
    final colors = context.theme.colors;
    return switch (level) {
      LogLevel.error || LogLevel.critical => semantic.danger,
      LogLevel.warning => semantic.warning,
      LogLevel.info => semantic.info,
      LogLevel.debug || LogLevel.verbose => colors.mutedForeground,
      _ => colors.mutedForeground,
    };
  }
}
