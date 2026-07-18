/// Privacy-safe, device-local history of Agent evidence navigation outcomes.
///
/// Events intentionally contain only a timestamp and whether GoRouter accepted
/// the navigation. Routes, artifact ids, evidence ids, and user text are never
/// persisted.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AgentEvidenceNavigationSummary {
  const AgentEvidenceNavigationSummary({
    required this.attempts,
    required this.successes,
  });

  final int attempts;
  final int successes;

  double get successRate => attempts == 0 ? 0 : successes / attempts;
}

abstract interface class AgentEvidenceNavigationStore {
  Future<void> record({required DateTime occurredAt, required bool succeeded});

  Future<AgentEvidenceNavigationSummary> summarize({required DateTime since});
}

class SharedPreferencesAgentEvidenceNavigationStore
    implements AgentEvidenceNavigationStore {
  SharedPreferencesAgentEvidenceNavigationStore(this._preferences);

  static const _key = 'naviwealth.agent.evidence_navigation.v1';
  static const _retention = Duration(days: 90);
  static const _maxEvents = 200;

  final SharedPreferences _preferences;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<void> record({required DateTime occurredAt, required bool succeeded}) {
    final eventTime = occurredAt.toUtc();
    Future<void> write() async {
      final oldestAllowed = eventTime.subtract(_retention);
      final events =
          _readEvents()
              .where((event) => !event.occurredAt.isBefore(oldestAllowed))
              .toList()
            ..add(_NavigationEvent(occurredAt: eventTime, succeeded: succeeded))
            ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      final bounded = events.length <= _maxEvents
          ? events
          : events.sublist(events.length - _maxEvents);
      await _preferences.setString(
        _key,
        jsonEncode(<Map<String, Object>>[
          for (final event in bounded) event.toJson(),
        ]),
      );
    }

    _pendingWrite = _pendingWrite.then(
      (_) => write(),
      onError: (_, _) => write(),
    );
    return _pendingWrite;
  }

  @override
  Future<AgentEvidenceNavigationSummary> summarize({
    required DateTime since,
  }) async {
    try {
      await _pendingWrite;
    } on Object {
      return const AgentEvidenceNavigationSummary(attempts: 0, successes: 0);
    }
    final windowStart = since.toUtc();
    final events = _readEvents().where(
      (event) => !event.occurredAt.isBefore(windowStart),
    );
    var attempts = 0;
    var successes = 0;
    for (final event in events) {
      attempts++;
      if (event.succeeded) successes++;
    }
    return AgentEvidenceNavigationSummary(
      attempts: attempts,
      successes: successes,
    );
  }

  List<_NavigationEvent> _readEvents() {
    final raw = _preferences.getString(_key);
    if (raw == null) return <_NavigationEvent>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return <_NavigationEvent>[];
      return decoded
          .map(_NavigationEvent.fromJson)
          .whereType<_NavigationEvent>()
          .toList(growable: true);
    } on FormatException {
      return <_NavigationEvent>[];
    }
  }
}

class _NavigationEvent {
  const _NavigationEvent({required this.occurredAt, required this.succeeded});

  final DateTime occurredAt;
  final bool succeeded;

  Map<String, Object> toJson() => <String, Object>{
    'at': occurredAt.toIso8601String(),
    'succeeded': succeeded,
  };

  static _NavigationEvent? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final at = value['at'];
    final succeeded = value['succeeded'];
    if (at is! String || succeeded is! bool) return null;
    final occurredAt = DateTime.tryParse(at)?.toUtc();
    if (occurredAt == null) return null;
    return _NavigationEvent(occurredAt: occurredAt, succeeded: succeeded);
  }
}
