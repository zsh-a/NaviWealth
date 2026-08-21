part of '_object_writers.dart';

class _ExperimentWriter extends ConsumerStatefulWidget {
  const _ExperimentWriter({
    this.initial,
    required this.dirty,
    this.focusEvidence = false,
  });
  final KnowledgeExperiment? initial;
  final FormDirtyController dirty;
  final bool focusEvidence;
  @override
  ConsumerState<_ExperimentWriter> createState() => _ExperimentWriterState();
}

class _ExperimentWriterState extends ConsumerState<_ExperimentWriter> {
  late final _hypoCtrl = TextEditingController(
    text: widget.initial?.hypothesis ?? '',
  );
  late final _methodCtrl = TextEditingController(
    text: widget.initial?.methodMd ?? '',
  );
  late final _metricsCtrl = TextEditingController(
    text: widget.initial?.metrics.join(', ') ?? '',
  );
  late final _resultCtrl = TextEditingController(
    text: widget.initial?.resultMd ?? '',
  );
  late final _conclusionCtrl = TextEditingController(
    text: widget.initial?.conclusionMd ?? '',
  );
  late ExperimentStatus _status =
      widget.initial?.status ?? ExperimentStatus.planned;
  late String? _targetAssumptionId = widget.initial?.targetAssumptionId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hypoCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    widget.dirty.bindTextControllers([
      _hypoCtrl,
      _methodCtrl,
      _metricsCtrl,
      _resultCtrl,
      _conclusionCtrl,
    ]);
  }

  @override
  void dispose() {
    _hypoCtrl.dispose();
    _methodCtrl.dispose();
    _metricsCtrl.dispose();
    _resultCtrl.dispose();
    _conclusionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _hypoCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final metrics = _metricsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      final existing = widget.initial;
      final sync = SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      );
      final result = _resultCtrl.text.trim();
      final conclusion = _conclusionCtrl.text.trim();
      final experiment = KnowledgeExperiment(
        id: existing?.id ?? kKnowledgeUuid.v4(),
        hypothesis: _hypoCtrl.text.trim(),
        methodMd: _methodCtrl.text,
        metrics: metrics,
        status: _status,
        targetAssumptionId: _targetAssumptionId,
        startedAt: existing?.startedAt ?? stamp.now,
        endedAt: _status == ExperimentStatus.done
            ? (existing?.endedAt ?? stamp.now)
            : existing?.endedAt,
        resultMd: result.isEmpty ? null : result,
        conclusionMd: conclusion.isEmpty ? null : conclusion,
        mergedIntoId: existing?.mergedIntoId,
        sync: sync,
      );
      if (_status == ExperimentStatus.done &&
          _targetAssumptionId != null &&
          conclusion.isNotEmpty) {
        await repo.completeExperiment(experiment: experiment, sync: sync);
      } else {
        await repo.upsertExperiment(experiment);
      }
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).commonSaveFailed,
        );
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeExperimentWriterTitle,
      subtitle: l10n.knowledgeExperimentWriterSubtitle2,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        enabled: _hypoCtrl.text.trim().isNotEmpty,
        onSubmit: () {
          _save();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterCoreSectionTitle,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _hypoCtrl),
                label: Text(l10n.knowledgeWriterHypothesisLabel),
                hint: l10n.knowledgeExperimentHypothesisHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterPlanningSectionTitle,
            children: [
              FSelect<ExperimentStatus>(
                items: {
                  for (final s in ExperimentStatus.values)
                    experimentStatusLabel(l10n, s): s,
                },
                control: FSelectControl<ExperimentStatus>.managed(
                  initial: _status,
                  onChange: (next) {
                    if (next == null) return;
                    setState(() => _status = next);
                    widget.dirty.markDirty();
                  },
                ),
                label: Text(l10n.knowledgeWriterStatusLabel),
              ),
              MarkdownEditorWithPreview(
                controller: _methodCtrl,
                label: l10n.knowledgeWriterMethodMarkdownLabel,
                hint: l10n.knowledgeExperimentMethodHint,
                minLines: 2,
                maxLines: 4,
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _metricsCtrl),
                label: Text(l10n.knowledgeWriterMetricsLabel),
                hint: l10n.knowledgeExperimentMetricsHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            collapsible: true,
            initiallyExpanded:
                widget.focusEvidence ||
                _status == ExperimentStatus.done ||
                _resultCtrl.text.isNotEmpty ||
                _conclusionCtrl.text.isNotEmpty,
            children: [
              MarkdownEditorWithPreview(
                controller: _resultCtrl,
                label: l10n.knowledgeWriterResultMarkdownLabel,
                minLines: 2,
                maxLines: 5,
              ),
              MarkdownEditorWithPreview(
                controller: _conclusionCtrl,
                label: l10n.knowledgeWriterConclusionMarkdownLabel,
                minLines: 2,
                maxLines: 5,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterReferencesSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              _AssumptionTargetPicker(
                selectedId: _targetAssumptionId,
                onChange: (id) {
                  setState(() => _targetAssumptionId = id);
                  widget.dirty.markDirty();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssumptionTargetPicker extends ConsumerWidget {
  const _AssumptionTargetPicker({
    required this.selectedId,
    required this.onChange,
  });
  final String? selectedId;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.watch(knowledgeOwnerUserIdProvider.future),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return const KnowledgeSectionSkeleton();
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const KnowledgeSectionSkeleton(),
          error: (e, stackTrace) => AppEmptyState.inline(
            icon: FLucideIcons.circleX,
            title: userSafeErrorMessage(
              context,
              e,
              stackTrace: stackTrace,
              operation: 'load knowledge assumptions',
            ),
            tone: AppEmptyStateTone.error,
            retryLabel: AppLocalizations.of(context).commonRetry,
            onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
          ),
          data: (repo) => StreamBuilder<List<KnowledgeAssumption>>(
            stream: repo.watchAssumptions(ownerUserId: owner),
            builder: (context, snap) {
              if (snap.hasError) {
                return AppEmptyState.inline(
                  icon: FLucideIcons.circleX,
                  title: userSafeErrorMessage(
                    context,
                    snap.error!,
                    stackTrace: snap.stackTrace,
                    operation: 'load knowledge experiment',
                  ),
                  tone: AppEmptyStateTone.error,
                );
              }
              final all = (snap.data ?? const <KnowledgeAssumption>[])
                  .where((a) => a.status == AssumptionStatus.active)
                  .toList(growable: false);
              if (all.isEmpty) {
                return AppEmptyState.inline(
                  icon: FLucideIcons.badgeCheck,
                  title: AppLocalizations.of(
                    context,
                  ).knowledgeExperimentNoActiveAssumptions,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(
                      context,
                    ).knowledgeExperimentTargetAssumptionLabel,
                    style: context.labelStyle,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  for (final a in all)
                    KnowledgeSelectableRow(
                      label: a.statement,
                      selected: selectedId == a.id,
                      mode: KnowledgeSelectionMode.radio,
                      onPress: () => onChange(selectedId == a.id ? null : a.id),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
