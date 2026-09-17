import '../../auth/domain_scope.dart';
import 'agent.dart';
import 'agent_schedule.dart';

/// Device-local, user-confirmed instructions. These never contain credentials
/// or executable code. All scheduled executions are read-only.
class ScheduledAgentTask {
  const ScheduledAgentTask({
    required this.id,
    required this.title,
    required this.instructions,
    required this.domain,
    required this.schedule,
    required this.createdAt,
    this.revision = 1,
    this.archived = false,
  });

  final String id;
  final String title;
  final String instructions;
  final DomainScope domain;
  final AgentSchedule schedule;
  final DateTime createdAt;
  final int revision;
  final bool archived;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'instructions': instructions,
    'domain': domain.wire,
    'weekday': schedule.weekdayLocal,
    'hour': schedule.preferredHourLocal,
    'minute': schedule.minuteLocal,
    'created_at': createdAt.toUtc().toIso8601String(),
    'revision': revision,
    'archived': archived,
  };

  factory ScheduledAgentTask.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    final instructions = json['instructions'];
    final domain = json['domain'] is String
        ? DomainScope.tryParse(json['domain']! as String)
        : null;
    final weekday = json['weekday'];
    final hour = json['hour'];
    final minute = json['minute'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 100 ||
        instructions is! String ||
        instructions.trim().isEmpty ||
        instructions.length > 4000 ||
        domain == null ||
        weekday is! int ||
        weekday < 1 ||
        weekday > 7 ||
        hour is! int ||
        hour < 0 ||
        hour > 23 ||
        minute is! int ||
        minute < 0 ||
        minute > 59) {
      throw const FormatException('Invalid scheduled task');
    }
    return ScheduledAgentTask(
      id: id,
      title: title.trim(),
      instructions: instructions.trim(),
      domain: domain,
      schedule: AgentSchedule.weekly(
        weekday: weekday,
        hour: hour,
        minute: minute,
      ),
      createdAt: DateTime.parse(json['created_at']! as String),
      revision: json['revision'] as int? ?? 1,
      archived: json['archived'] as bool? ?? false,
    );
  }
}

typedef ScheduledAgentExecute = Future<AgentRunResult> Function(
  ScheduledAgentTask task,
  AgentContext context,
);

class ScheduledLlmAgent implements Agent {
  const ScheduledLlmAgent(this.task, this.execute);
  final ScheduledAgentTask task;
  final ScheduledAgentExecute execute;
  @override
  String get id => task.id;
  @override
  String get name => task.title;
  @override
  AgentSchedule get schedule => task.schedule;
  @override
  Future<AgentRunResult> run(AgentContext ctx) => execute(task, ctx);
}
