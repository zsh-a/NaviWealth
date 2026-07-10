/// AI Transparency surface.
///
/// Two pages:
///   - [AiTransparencyPage]: newest-first list of recent traces, one
///     compact row per turn. The row carries the chips that matter
///     most for quick scanning (backend, duration, terminal reason,
///     tool count, stale count).
///   - [AiTransparencyDetailPage]: Opik-style span tree + waterfall
///     of the selected trace, with a per-span detail panel. See
///     `transparency/trace_waterfall.dart`.
///
/// The list page intentionally stays thin so the detail page does the
/// heavy lifting.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/contracts/contracts.dart';
import '../../../../core/ai/trace/ai_trace_capture_preference.dart';
import '../../../../core/ai/trace/providers.dart';
import '../../../../core/ai/visual/visual.dart';
import '../../../../core/ai/write/drift_undo_stack.dart';
import '../../../../core/ai/write/persisted_undo_dispatcher.dart';
import '../../../../core/ai/write/providers.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import 'transparency/trace_waterfall.dart';

part 'transparency/detail.dart';
part 'transparency/header.dart';
part 'transparency/helpers.dart';
part 'transparency/trace_list.dart';
part 'transparency/undo.dart';

class AiTransparencyPage extends ConsumerStatefulWidget {
  const AiTransparencyPage({super.key});

  @override
  ConsumerState<AiTransparencyPage> createState() => _AiTransparencyPageState();
}

class _AiTransparencyPageState extends ConsumerState<AiTransparencyPage> {
  bool _errorsOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tracesAsync = ref.watch(recentAiTracesProvider);
    return AppPageScaffold(
      title: l10n.settingsAiTransparencyTitle,
      childPad: false,
      child: CustomScrollView(
        slivers: <Widget>[
          const SliverToBoxAdapter(child: _UndoSection()),
          const SliverToBoxAdapter(child: _CaptureToggle()),
          tracesAsync.when(
            data: (traces) {
              if (traces.isEmpty) {
                return const SliverToBoxAdapter(child: _EmptyState());
              }
              final shown = _errorsOnly
                  ? traces
                        .where((t) => t.terminalReason != TerminalReason.done)
                        .toList(growable: false)
                  : traces;
              return SliverMainAxisGroup(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: _AggregateHeader(
                      traces: traces,
                      errorsOnly: _errorsOnly,
                      onToggleErrors: () =>
                          setState(() => _errorsOnly = !_errorsOnly),
                    ),
                  ),
                  if (shown.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s24),
                        child: Center(
                          child: Text(l10n.aiTransparencyFilteredEmpty),
                        ),
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.s16,
                        ),
                        child: FDivider(),
                      ),
                      itemBuilder: (context, i) => _TraceRow(trace: shown[i]),
                    ),
                ],
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(child: FCircularProgress()),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text(userSafeErrorMessage(context, e))),
            ),
          ),
        ],
      ),
    );
  }
}

class AiTransparencyDetailPage extends ConsumerWidget {
  const AiTransparencyDetailPage({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final traceAsync = ref.watch(aiTraceByIdProvider(requestId));
    return AppPageScaffold(
      title: l10n.aiTransparencyDetailTitle,
      childPad: false,
      child: traceAsync.whenOrLoading(
        context: context,
        data: (trace) {
          if (trace == null) {
            return Center(child: Text(l10n.aiTransparencyTraceNotFound));
          }
          return _TraceWaterfallBody(trace: trace);
        },
        error: (e, _) => Center(child: Text(userSafeErrorMessage(context, e))),
      ),
    );
  }
}
