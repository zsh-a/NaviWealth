import '../../../core/sync/sync_meta.dart';

enum ExecutionActionStatus {
  todo('todo'),
  doing('doing'),
  blocked('blocked'),
  done('done'),
  dropped('dropped');

  const ExecutionActionStatus(this.wire);
  final String wire;

  static ExecutionActionStatus parse(String value) {
    return ExecutionActionStatus.values.firstWhere(
      (s) => s.wire == value,
      orElse: () => ExecutionActionStatus.todo,
    );
  }
}

enum ExecutionPriority {
  low('low'),
  normal('normal'),
  high('high');

  const ExecutionPriority(this.wire);
  final String wire;

  static ExecutionPriority parse(String value) {
    return ExecutionPriority.values.firstWhere(
      (p) => p.wire == value,
      orElse: () => ExecutionPriority.normal,
    );
  }
}

enum ExecutionCommitmentStatus {
  active('active'),
  paused('paused'),
  completed('completed'),
  archived('archived');

  const ExecutionCommitmentStatus(this.wire);
  final String wire;

  static ExecutionCommitmentStatus parse(String value) {
    return ExecutionCommitmentStatus.values.firstWhere(
      (s) => s.wire == value,
      orElse: () => ExecutionCommitmentStatus.active,
    );
  }

  bool get isOpen =>
      this == ExecutionCommitmentStatus.active ||
      this == ExecutionCommitmentStatus.paused;
}

enum ExecutionProjectStatus {
  active('active'),
  paused('paused'),
  completed('completed'),
  archived('archived');

  const ExecutionProjectStatus(this.wire);
  final String wire;

  static ExecutionProjectStatus parse(String value) {
    return ExecutionProjectStatus.values.firstWhere(
      (s) => s.wire == value,
      orElse: () => ExecutionProjectStatus.active,
    );
  }

  bool get isOpen =>
      this == ExecutionProjectStatus.active ||
      this == ExecutionProjectStatus.paused;
}

enum ExecutionHorizon {
  week('week'),
  month('month'),
  quarter('quarter'),
  open('open');

  const ExecutionHorizon(this.wire);
  final String wire;

  static ExecutionHorizon parse(String value) {
    return ExecutionHorizon.values.firstWhere(
      (h) => h.wire == value,
      orElse: () => ExecutionHorizon.open,
    );
  }
}

enum ExecutionProgressKind {
  checkin('checkin'),
  blocker('blocker'),
  scopeChange('scopeChange'),
  completion('completion'),
  dropped('dropped');

  const ExecutionProgressKind(this.wire);
  final String wire;

  static ExecutionProgressKind parse(String value) {
    return ExecutionProgressKind.values.firstWhere(
      (k) => k.wire == value,
      orElse: () => ExecutionProgressKind.checkin,
    );
  }
}

class ExecutionSourceRef {
  const ExecutionSourceRef({
    this.domain,
    this.rowFamily,
    this.rowId,
    this.labelSnapshot,
  });

  final String? domain;
  final String? rowFamily;
  final String? rowId;
  final String? labelSnapshot;

  bool get isEmpty =>
      (domain == null || domain!.isEmpty) &&
      (rowFamily == null || rowFamily!.isEmpty) &&
      (rowId == null || rowId!.isEmpty);
}

class ExecutionAction {
  const ExecutionAction({
    required this.id,
    required this.title,
    this.note = '',
    this.status = ExecutionActionStatus.todo,
    this.priority = ExecutionPriority.normal,
    this.dueAt,
    this.scheduledFor,
    this.projectId,
    this.commitmentId,
    this.source = const ExecutionSourceRef(),
    required this.createdAt,
    this.completedAt,
    required this.sync,
  });

  final String id;
  final String title;
  final String note;
  final ExecutionActionStatus status;
  final ExecutionPriority priority;
  final DateTime? dueAt;
  final DateTime? scheduledFor;
  final String? projectId;
  final String? commitmentId;
  final ExecutionSourceRef source;
  final DateTime createdAt;
  final DateTime? completedAt;
  final SyncMeta sync;

  bool get isOpen =>
      status == ExecutionActionStatus.todo ||
      status == ExecutionActionStatus.doing ||
      status == ExecutionActionStatus.blocked;

  bool get isBacklog =>
      status == ExecutionActionStatus.todo &&
      scheduledFor == null &&
      dueAt == null;

  bool isDue(DateTime now) {
    final due = dueAt;
    if (due == null) return false;
    return !due.toLocal().isAfter(now.toLocal());
  }

  ExecutionAction copyWith({
    String? title,
    String? note,
    ExecutionActionStatus? status,
    ExecutionPriority? priority,
    Object? dueAt = _sentinel,
    Object? scheduledFor = _sentinel,
    Object? projectId = _sentinel,
    Object? commitmentId = _sentinel,
    ExecutionSourceRef? source,
    Object? completedAt = _sentinel,
    required SyncMeta sync,
  }) {
    return ExecutionAction(
      id: id,
      title: title ?? this.title,
      note: note ?? this.note,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueAt: dueAt == _sentinel ? this.dueAt : dueAt as DateTime?,
      scheduledFor: scheduledFor == _sentinel
          ? this.scheduledFor
          : scheduledFor as DateTime?,
      projectId: projectId == _sentinel ? this.projectId : projectId as String?,
      commitmentId: commitmentId == _sentinel
          ? this.commitmentId
          : commitmentId as String?,
      source: source ?? this.source,
      createdAt: createdAt,
      completedAt: completedAt == _sentinel
          ? this.completedAt
          : completedAt as DateTime?,
      sync: sync,
    );
  }
}

class ExecutionProject {
  const ExecutionProject({
    required this.id,
    required this.title,
    this.description = '',
    this.status = ExecutionProjectStatus.active,
    this.horizon = ExecutionHorizon.open,
    this.targetDate,
    this.source = const ExecutionSourceRef(),
    required this.createdAt,
    this.completedAt,
    required this.sync,
  });

  final String id;
  final String title;
  final String description;
  final ExecutionProjectStatus status;
  final ExecutionHorizon horizon;
  final DateTime? targetDate;
  final ExecutionSourceRef source;
  final DateTime createdAt;
  final DateTime? completedAt;
  final SyncMeta sync;

  ExecutionProject copyWith({
    String? title,
    String? description,
    ExecutionProjectStatus? status,
    ExecutionHorizon? horizon,
    Object? targetDate = _sentinel,
    ExecutionSourceRef? source,
    Object? completedAt = _sentinel,
    required SyncMeta sync,
  }) {
    return ExecutionProject(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      horizon: horizon ?? this.horizon,
      targetDate: targetDate == _sentinel
          ? this.targetDate
          : targetDate as DateTime?,
      source: source ?? this.source,
      createdAt: createdAt,
      completedAt: completedAt == _sentinel
          ? this.completedAt
          : completedAt as DateTime?,
      sync: sync,
    );
  }
}

class ExecutionCommitment {
  const ExecutionCommitment({
    required this.id,
    required this.title,
    this.description = '',
    this.status = ExecutionCommitmentStatus.active,
    this.horizon = ExecutionHorizon.open,
    this.targetDate,
    this.projectId,
    this.source = const ExecutionSourceRef(),
    required this.createdAt,
    this.completedAt,
    required this.sync,
  });

  final String id;
  final String title;
  final String description;
  final ExecutionCommitmentStatus status;
  final ExecutionHorizon horizon;
  final DateTime? targetDate;
  final String? projectId;
  final ExecutionSourceRef source;
  final DateTime createdAt;
  final DateTime? completedAt;
  final SyncMeta sync;

  ExecutionCommitment copyWith({
    String? title,
    String? description,
    ExecutionCommitmentStatus? status,
    ExecutionHorizon? horizon,
    Object? targetDate = _sentinel,
    Object? projectId = _sentinel,
    ExecutionSourceRef? source,
    Object? completedAt = _sentinel,
    required SyncMeta sync,
  }) {
    return ExecutionCommitment(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      horizon: horizon ?? this.horizon,
      targetDate: targetDate == _sentinel
          ? this.targetDate
          : targetDate as DateTime?,
      projectId: projectId == _sentinel ? this.projectId : projectId as String?,
      source: source ?? this.source,
      createdAt: createdAt,
      completedAt: completedAt == _sentinel
          ? this.completedAt
          : completedAt as DateTime?,
      sync: sync,
    );
  }
}

class ExecutionProgressEntry {
  const ExecutionProgressEntry({
    required this.id,
    this.actionId,
    this.projectId,
    this.commitmentId,
    required this.kind,
    required this.note,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String? actionId;
  final String? projectId;
  final String? commitmentId;
  final ExecutionProgressKind kind;
  final String note;
  final DateTime createdAt;
  final SyncMeta sync;
}

class ExecutionOverviewSnapshot {
  const ExecutionOverviewSnapshot({
    required this.todayCount,
    required this.blockedCount,
    required this.openCount,
    required this.backlogCount,
    required this.highPriorityCount,
    required this.dueCount,
    required this.activeProjectCount,
    required this.activeCommitmentCount,
    required this.recentProgressCount,
  });

  final int todayCount;
  final int blockedCount;
  final int openCount;
  final int backlogCount;
  final int highPriorityCount;
  final int dueCount;
  final int activeProjectCount;
  final int activeCommitmentCount;
  final int recentProgressCount;

  factory ExecutionOverviewSnapshot.fromLists({
    required List<ExecutionAction> todayActions,
    required List<ExecutionAction> openActions,
    required List<ExecutionProject> projects,
    required List<ExecutionCommitment> commitments,
    required List<ExecutionProgressEntry> recentProgress,
    required DateTime now,
  }) {
    final open = openActions.where((action) => action.isOpen).toList();
    final recentSince = now.toLocal().subtract(const Duration(days: 7));
    return ExecutionOverviewSnapshot(
      todayCount: todayActions.length,
      blockedCount: open
          .where((action) => action.status == ExecutionActionStatus.blocked)
          .length,
      openCount: open.length,
      backlogCount: open.where((action) => action.isBacklog).length,
      highPriorityCount: open
          .where((action) => action.priority == ExecutionPriority.high)
          .length,
      dueCount: open.where((action) => action.isDue(now)).length,
      activeProjectCount: projects.length,
      activeCommitmentCount: commitments.length,
      recentProgressCount: recentProgress
          .where((entry) => !entry.createdAt.toLocal().isBefore(recentSince))
          .length,
    );
  }
}

/// Marker used so `copyWith` can distinguish omitted nullable fields from
/// fields explicitly cleared to null.
const Object _sentinel = Object();
