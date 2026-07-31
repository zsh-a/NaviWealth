part of '_decision_writer.dart';

class _PrincipleAssumptionPicker extends ConsumerWidget {
  const _PrincipleAssumptionPicker({
    required this.principleIds,
    required this.assumptionIds,
    required this.onPrincipleToggle,
    required this.onAssumptionToggle,
  });
  final Set<String> principleIds;
  final Set<String> assumptionIds;
  final ValueChanged<String> onPrincipleToggle;
  final ValueChanged<String> onAssumptionToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.watch(knowledgeOwnerUserIdProvider.future),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return const KnowledgeLoadingState(
            density: KnowledgeStateDensity.section,
          );
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const KnowledgeLoadingState(
            density: KnowledgeStateDensity.section,
          ),
          error: (e, stackTrace) => KnowledgeErrorState(
            title: userSafeErrorMessage(
              context,
              e,
              stackTrace: stackTrace,
              operation: 'load knowledge principles',
            ),
            onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
            density: KnowledgeStateDensity.section,
          ),
          data: (repo) => StreamBuilder<List<KnowledgePrinciple>>(
            stream: repo.watchPrinciples(ownerUserId: owner),
            builder: (context, principlesSnap) {
              if (principlesSnap.hasError) {
                return KnowledgeErrorState(
                  title: userSafeErrorMessage(
                    context,
                    principlesSnap.error!,
                    stackTrace: principlesSnap.stackTrace,
                    operation: 'load decision principles',
                  ),
                  density: KnowledgeStateDensity.section,
                );
              }
              return StreamBuilder<List<KnowledgeAssumption>>(
                stream: repo.watchAssumptions(ownerUserId: owner),
                builder: (context, assumptionsSnap) {
                  if (assumptionsSnap.hasError) {
                    return KnowledgeErrorState(
                      title: userSafeErrorMessage(
                        context,
                        assumptionsSnap.error!,
                        stackTrace: assumptionsSnap.stackTrace,
                        operation: 'load decision assumptions',
                      ),
                      density: KnowledgeStateDensity.section,
                    );
                  }
                  final principles =
                      (principlesSnap.data ?? const <KnowledgePrinciple>[])
                          .where((p) => p.status == PrincipleStatus.active)
                          .toList(growable: false);
                  final assumptions =
                      (assumptionsSnap.data ?? const <KnowledgeAssumption>[])
                          .where((a) => a.status == AssumptionStatus.active)
                          .toList(growable: false);
                  if (principles.isEmpty && assumptions.isEmpty) {
                    return KnowledgeEmptyState(
                      icon: FLucideIcons.link,
                      title: AppLocalizations.of(
                        context,
                      ).knowledgeDecisionNoReferenceCandidates,
                      density: KnowledgeStateDensity.section,
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (principles.isNotEmpty) ...[
                        _SectionLabel(
                          text: AppLocalizations.of(
                            context,
                          ).knowledgeDetailPrinciplesTitle,
                        ),
                        _CheckboxList(
                          items: principles
                              .map(
                                (p) => _CheckboxItem(
                                  id: p.id,
                                  label: p.statement,
                                  selected: principleIds.contains(p.id),
                                ),
                              )
                              .toList(growable: false),
                          onToggle: onPrincipleToggle,
                        ),
                      ],
                      if (assumptions.isNotEmpty) ...[
                        if (principles.isNotEmpty)
                          const SizedBox(height: AppSpacing.s8),
                        _SectionLabel(
                          text: AppLocalizations.of(
                            context,
                          ).knowledgeDetailAssumptionsTitle,
                        ),
                        _CheckboxList(
                          items: assumptions
                              .map(
                                (a) => _CheckboxItem(
                                  id: a.id,
                                  label:
                                      '${a.statement}（conf ${a.confidence.toStringAsFixed(2)}）',
                                  selected: assumptionIds.contains(a.id),
                                ),
                              )
                              .toList(growable: false),
                          onToggle: onAssumptionToggle,
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s4),
    child: Text(text, style: context.labelStyle),
  );
}

class _CheckboxItem {
  const _CheckboxItem({
    required this.id,
    required this.label,
    required this.selected,
  });
  final String id;
  final String label;
  final bool selected;
}

class _CheckboxList extends StatelessWidget {
  const _CheckboxList({required this.items, required this.onToggle});
  final List<_CheckboxItem> items;
  final ValueChanged<String> onToggle;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          KnowledgeSelectableRow(
            label: item.label,
            selected: item.selected,
            onPress: () => onToggle(item.id),
          ),
      ],
    );
  }
}
