import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:talker/talker.dart';

import '../../core/logging/providers.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final talker = ref.watch(talkerProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.settingsLogsTitle),
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.delete_outline),
            onPress: () {
              talker.cleanHistory();
              setState(() {});
            },
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: StreamBuilder<TalkerData>(
          stream: talker.stream,
          builder: (context, _) {
            final logs = talker.history;
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return _LogTile(log: log);
              },
            );
          },
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final TalkerData log;

  @override
  Widget build(BuildContext context) {
    final color = _colorForLevel(log.logLevel);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.title ?? log.logLevel?.name ?? 'log',
                      style: context.theme.typography.xs2.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    log.displayTime(),
                    style: context.theme.typography.xs2.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(log.message ?? '', style: context.theme.typography.xs),
              if (log.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${log.error}',
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.destructive,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _colorForLevel(LogLevel? level) {
    return switch (level) {
      LogLevel.error => const Color(0xFFE53935),
      LogLevel.critical => const Color(0xFFD32F2F),
      LogLevel.warning => const Color(0xFFFFA726),
      LogLevel.info => const Color(0xFF42A5F5),
      LogLevel.debug => const Color(0xFF78909C),
      LogLevel.verbose => const Color(0xFF90A4AE),
      _ => const Color(0xFF90A4AE),
    };
  }
}
