part of 'investment_portfolio_repository.dart';

mixin InvestmentPortfolioRepositoryWriteMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;
  MutationStamper get _stamper;
  PortfolioStrategyRegistry get _strategyRegistry;

  Future<RebalanceUniverse> _ensureDefaultUniverse({
    required String ownerUserId,
    required String baseCurrency,
    required MutationStamp stamp,
  });

  Future<List<PortfolioAllocationTargetRow>> _activePortfolioTargetRows(
    String universeId,
  );

  Future<List<PortfolioRebalanceGroupRow>> _activeGroupRows(String portfolioId);

  Future<void> _requireActiveGroup(String portfolioId, String groupId);

  PortfolioStrategyTemplatesCompanion _strategyTemplateCompanion(
    PortfolioStrategyTemplate template,
  );

  PortfolioStrategyConfigsCompanion _strategyCompanion(
    PortfolioStrategyConfig strategy,
  );

  /// Creates one complete, valid portfolio aggregate in a single transaction.
  ///
  /// The first strategy owns the default 100% rebalance group. Additional
  /// owner or overlay modules can be attached independently afterwards.
  Future<InvestmentPortfolio> create({
    required String name,
    required PortfolioStrategyTemplate initialStrategy,
    required String baseCurrency,
    required String languageCode,
    String? goalId,
    String? color,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    initialStrategy.validate();
    if (initialStrategy.defaultCapitalRole != StrategyCapitalRole.owner) {
      throw ArgumentError.value(
        initialStrategy.kind.wire,
        'initialStrategy',
        'must own capital',
      );
    }
    final stamp = await _stamper.stamp();
    final portfolioId = _uuid.v4();
    final kind = initialStrategy.kind;
    final groupId = _uuid.v4();
    final strategyId = _uuid.v4();
    final normalizedCurrency = baseCurrency.trim().toUpperCase();
    if (normalizedCurrency.length < 3 || normalizedCurrency.length > 8) {
      throw ArgumentError.value(
        baseCurrency,
        'baseCurrency',
        'must contain 3 to 8 characters',
      );
    }
    final portfolio = InvestmentPortfolio(
      id: portfolioId,
      name: normalizedName,
      baseCurrency: normalizedCurrency,
      goalId: _nullableTrimmed(goalId),
      color: _nullableTrimmed(color),
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    final group = PortfolioRebalanceGroup(
      id: groupId,
      portfolioId: portfolioId,
      name: initialStrategy.displayName(languageCode),
      strategyKind: kind,
      targetWeightBps: 10000,
      driftBandBps: initialStrategy.defaultDriftBandBps,
      transferPolicy: initialStrategy.defaultTransferPolicy,
      internalTarget: initialStrategy.defaultInternalTarget,
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    final strategy = PortfolioStrategyConfig(
      id: strategyId,
      portfolioId: portfolioId,
      kind: kind,
      schemaVersion: initialStrategy.schemaVersion,
      enabled: true,
      capitalRole: initialStrategy.defaultCapitalRole,
      rebalanceGroupId: groupId,
      settings: initialStrategy.defaultSettings,
      sync: _syncFromStamp(stamp),
    );

    await _db.transaction(() async {
      final universe = await _ensureDefaultUniverse(
        ownerUserId: stamp.ownerUserId,
        baseCurrency: normalizedCurrency,
        stamp: stamp,
      );
      final existingTargets = await _activePortfolioTargetRows(universe.id);
      final portfolioTarget = PortfolioAllocationTarget(
        id: portfolioAllocationTargetId(universe.id, portfolioId),
        universeId: universe.id,
        portfolioId: portfolioId,
        targetWeightBps: existingTargets.isEmpty ? 10000 : 0,
        driftBandBps: 500,
        transferPolicy: GroupTransferPolicy.bidirectional,
        sync: _syncFromStamp(stamp),
      );
      await _db
          .into(_db.investmentPortfolios)
          .insert(_portfolioCompanion(portfolio));
      await _db
          .into(_db.portfolioAllocationTargets)
          .insert(_portfolioTargetCompanion(portfolioTarget));
      await _db
          .into(_db.portfolioRebalanceGroups)
          .insert(_groupCompanion(group));
      await _db
          .into(_db.portfolioStrategyConfigs)
          .insert(_strategyCompanion(strategy));
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
      await _outbox.enqueue(
        table: portfolioTargetsTable,
        rowId: portfolioTarget.id,
      );
      await _outbox.enqueue(table: groupsTable, rowId: group.id);
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return portfolio;
  }

  Future<PortfolioStrategyTemplate> createCustomStrategyTemplate({
    required String name,
    required String languageCode,
    required String iconToken,
    required StrategyCapitalRole capitalRole,
    required TargetAllocation defaultInternalTarget,
    required int defaultDriftBandBps,
    required GroupTransferPolicy defaultTransferPolicy,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final stamp = await _stamper.stamp();
    final template = PortfolioStrategyTemplate(
      kind: PortfolioStrategyKind('user:${_uuid.v4()}'),
      localizedNames: {
        (languageCode.trim().isEmpty ? 'en' : languageCode.trim()):
            normalizedName,
      },
      iconToken: iconToken.trim().isEmpty ? 'layers' : iconToken.trim(),
      schemaVersion: 1,
      defaultCapitalRole: capitalRole,
      defaultSettings: const OpaquePortfolioStrategySettings({}),
      defaultInternalTarget: defaultInternalTarget,
      defaultDriftBandBps: defaultDriftBandBps,
      defaultTransferPolicy: defaultTransferPolicy,
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    template.validate();
    await _db.transaction(() async {
      await _db
          .into(_db.portfolioStrategyTemplates)
          .insert(_strategyTemplateCompanion(template));
      await _outbox.enqueue(
        table: strategyTemplatesTable,
        rowId: template.kind.wire,
      );
    });
    return template;
  }

  Future<PortfolioStrategyTemplate> updateCustomStrategyTemplate({
    required PortfolioStrategyTemplate template,
    required String name,
    required String languageCode,
    required TargetAllocation defaultInternalTarget,
    required int defaultDriftBandBps,
    required GroupTransferPolicy defaultTransferPolicy,
  }) async {
    if (template.isBuiltIn) {
      throw ArgumentError.value(template, 'template', 'must be custom');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final stamp = await _stamper.stamp();
    final updated = template.copyWith(
      localizedNames: {
        ...template.localizedNames,
        (languageCode.trim().isEmpty ? 'en' : languageCode.trim()):
            normalizedName,
      },
      defaultInternalTarget: defaultInternalTarget,
      defaultDriftBandBps: defaultDriftBandBps,
      defaultTransferPolicy: defaultTransferPolicy,
      sync: _syncFromStamp(stamp),
    );
    updated.validate();
    await _db.transaction(() async {
      await (_db.update(_db.portfolioStrategyTemplates)
            ..where((table) => table.id.equals(template.kind.wire)))
          .write(_strategyTemplateCompanion(updated));
      await _outbox.enqueue(
        table: strategyTemplatesTable,
        rowId: updated.kind.wire,
      );
    });
    return updated;
  }

  Future<void> archiveCustomStrategyTemplate(
    PortfolioStrategyTemplate template,
  ) async {
    if (template.isBuiltIn) {
      throw ArgumentError.value(template, 'template', 'must be custom');
    }
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.portfolioStrategyTemplates,
      )..where((table) => table.id.equals(template.kind.wire))).write(
        PortfolioStrategyTemplatesCompanion(
          archived: const Value(true),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(
        table: strategyTemplatesTable,
        rowId: template.kind.wire,
      );
    });
  }

  Future<InvestmentPortfolio> update(InvestmentPortfolio portfolio) async {
    final normalizedName = portfolio.name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(portfolio.name, 'name', 'must not be empty');
    }
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.investmentPortfolios,
      )..where((table) => table.id.equals(portfolio.id))).write(
        InvestmentPortfoliosCompanion(
          name: Value(normalizedName),
          baseCurrency: Value(portfolio.baseCurrency),
          goalId: Value(portfolio.goalId),
          color: Value(portfolio.color),
          archived: Value(portfolio.archived),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
    });
    return portfolio.copyWith(
      name: normalizedName,
      sync: _syncFromStamp(stamp),
    );
  }

  Future<PortfolioStrategyConfig> updateStrategy(
    PortfolioStrategyConfig strategy,
  ) async {
    final definition = _strategyRegistry.definitionFor(strategy.kind);
    final issues = definition?.validate(strategy.settings) ?? const <String>[];
    if (issues.isNotEmpty) {
      throw ArgumentError.value(issues, 'strategy', issues.join('; '));
    }
    final stamp = await _stamper.stamp();
    final updated = strategy.copyWith(sync: _syncFromStamp(stamp));
    await _db.transaction(() async {
      await (_db.update(_db.portfolioStrategyConfigs)
            ..where((table) => table.id.equals(strategy.id)))
          .write(_strategyCompanion(updated));
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return updated;
  }

  /// Adds a capital-owning strategy module and its group atomically.
  ///
  /// New groups start at 0% so adding one never silently changes the existing
  /// plan. The collection editor is the only place that redistributes capital.
  Future<PortfolioRebalanceGroup> addCapitalStrategy({
    required String portfolioId,
    required PortfolioStrategyTemplate template,
    String? groupName,
  }) async {
    template.validate();
    if (template.defaultCapitalRole != StrategyCapitalRole.owner) {
      throw ArgumentError.value(
        template.kind.wire,
        'template',
        'must own capital',
      );
    }
    final kind = template.kind;
    final stamp = await _stamper.stamp();
    final groupId = _uuid.v4();
    final strategyId = _uuid.v4();
    late final PortfolioRebalanceGroup created;
    await _db.transaction(() async {
      final existing = await _activeGroupRows(portfolioId);
      created = PortfolioRebalanceGroup(
        id: groupId,
        portfolioId: portfolioId,
        name: _nullableTrimmed(groupName) ?? template.displayName('en'),
        strategyKind: kind,
        targetWeightBps: existing.isEmpty ? 10000 : 0,
        driftBandBps: template.defaultDriftBandBps,
        transferPolicy: template.defaultTransferPolicy,
        internalTarget: template.defaultInternalTarget,
        createdAt: stamp.now,
        archived: false,
        sync: _syncFromStamp(stamp),
      );
      final strategy = PortfolioStrategyConfig(
        id: strategyId,
        portfolioId: portfolioId,
        kind: kind,
        schemaVersion: template.schemaVersion,
        enabled: true,
        capitalRole: StrategyCapitalRole.owner,
        rebalanceGroupId: groupId,
        settings: template.defaultSettings,
        sync: _syncFromStamp(stamp),
      );
      await _db
          .into(_db.portfolioRebalanceGroups)
          .insert(_groupCompanion(created));
      await _db
          .into(_db.portfolioStrategyConfigs)
          .insert(_strategyCompanion(strategy));
      await _outbox.enqueue(table: groupsTable, rowId: created.id);
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return created;
  }

  /// Attaches a non-capital-owning module to an existing group.
  Future<PortfolioStrategyConfig> addStrategyOverlay({
    required String portfolioId,
    required String rebalanceGroupId,
    required PortfolioStrategyTemplate template,
  }) async {
    template.validate();
    final kind = template.kind;
    await _requireActiveGroup(portfolioId, rebalanceGroupId);
    final stamp = await _stamper.stamp();
    final strategy = PortfolioStrategyConfig(
      id: _uuid.v4(),
      portfolioId: portfolioId,
      kind: kind,
      schemaVersion: template.schemaVersion,
      enabled: true,
      capitalRole: StrategyCapitalRole.overlay,
      rebalanceGroupId: rebalanceGroupId,
      settings: template.defaultSettings,
      sync: _syncFromStamp(stamp),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.portfolioStrategyConfigs)
          .insert(_strategyCompanion(strategy));
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return strategy;
  }

  /// Replaces every active portfolio target in one universe atomically.
  ///
  /// Callers must submit the complete sibling set. This keeps redistribution
  /// explicit in the UI instead of mutating hidden rows as a side effect of
  /// editing one percentage.
  Future<List<PortfolioAllocationTarget>> updatePortfolioPlan({
    required String universeId,
    required List<PortfolioAllocationTarget> targets,
  }) async {
    if (targets.isEmpty ||
        targets.any(
          (target) => target.universeId != universeId || !target.isValid,
        ) ||
        targets.fold<int>(0, (sum, target) => sum + target.targetWeightBps) !=
            10000) {
      throw ArgumentError.value(
        targets,
        'targets',
        'must be the complete valid 100% universe allocation',
      );
    }
    final stamp = await _stamper.stamp();
    final updated = [
      for (final target in targets)
        target.copyWith(sync: _syncFromStamp(stamp)),
    ];
    await _db.transaction(() async {
      final rows = await _activePortfolioTargetRows(universeId);
      final activeIds = {for (final row in rows) row.id};
      final submittedIds = {for (final target in targets) target.id};
      if (activeIds.length != submittedIds.length ||
          !activeIds.containsAll(submittedIds)) {
        throw StateError('Portfolio plan changed while it was being edited.');
      }
      for (final target in updated) {
        await (_db.update(_db.portfolioAllocationTargets)
              ..where((table) => table.id.equals(target.id)))
            .write(_portfolioTargetCompanion(target));
        await _outbox.enqueue(table: portfolioTargetsTable, rowId: target.id);
      }
    });
    return List.unmodifiable(updated);
  }

  /// Replaces every active capital-owning strategy in one portfolio
  /// atomically. The sibling weights must total exactly 100%.
  Future<List<PortfolioRebalanceGroup>> updateStrategyPlan({
    required String portfolioId,
    required List<PortfolioRebalanceGroup> groups,
  }) async {
    if (groups.isEmpty ||
        groups.any(
          (group) =>
              group.portfolioId != portfolioId ||
              group.name.trim().isEmpty ||
              !group.hasValidWeight ||
              !group.internalTarget.isValid,
        ) ||
        groups.fold<int>(0, (sum, group) => sum + group.targetWeightBps) !=
            10000) {
      throw ArgumentError.value(
        groups,
        'groups',
        'must be the complete valid 100% strategy allocation',
      );
    }
    final stamp = await _stamper.stamp();
    final updated = [
      for (final group in groups)
        group.copyWith(name: group.name.trim(), sync: _syncFromStamp(stamp)),
    ];
    await _db.transaction(() async {
      final rows = await _activeGroupRows(portfolioId);
      final activeIds = {for (final row in rows) row.id};
      final submittedIds = {for (final group in groups) group.id};
      if (activeIds.length != submittedIds.length ||
          !activeIds.containsAll(submittedIds)) {
        throw StateError('Strategy plan changed while it was being edited.');
      }
      for (final group in updated) {
        await (_db.update(_db.portfolioRebalanceGroups)
              ..where((table) => table.id.equals(group.id)))
            .write(_groupCompanion(group));
        await _outbox.enqueue(table: groupsTable, rowId: group.id);
      }
    });
    return List.unmodifiable(updated);
  }

  Future<PortfolioRebalanceGroup> updateGroup(
    PortfolioRebalanceGroup group,
  ) async {
    if (!group.hasValidWeight || !group.internalTarget.isValid) {
      throw ArgumentError.value(group, 'group', 'contains invalid weights');
    }
    final activeGroups = await _activeGroupRows(group.portfolioId);
    final aggregateWeight = activeGroups.fold<int>(
      0,
      (sum, row) =>
          sum +
          (row.id == group.id ? group.targetWeightBps : row.targetWeightBps),
    );
    if (aggregateWeight != 10000) {
      throw ArgumentError.value(
        group.targetWeightBps,
        'targetWeightBps',
        'use updateStrategyPlan to save the complete 100% allocation',
      );
    }
    final stamp = await _stamper.stamp();
    final updated = group.copyWith(sync: _syncFromStamp(stamp));
    await _db.transaction(() async {
      await (_db.update(_db.portfolioRebalanceGroups)
            ..where((table) => table.id.equals(group.id)))
          .write(_groupCompanion(updated));
      await _outbox.enqueue(table: groupsTable, rowId: group.id);
    });
    return updated;
  }
}
