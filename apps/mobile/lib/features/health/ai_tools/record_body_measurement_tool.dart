/// `record_body_measurement` — HealthOS low-frequency manual write tool.
///
/// Used for user-explicit statements such as "记录今天体重 72.4kg" or
/// "体脂 18.5%". It writes the same canonical HealthMetric rows as the
/// manual sheet.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../data/providers.dart';
import '../domain/health_metric_kind.dart';

class RecordBodyMeasurementTool implements DeviceTool {
  const RecordBodyMeasurementTool();

  @override
  String get name => 'record_body_measurement';

  @override
  String get description =>
      '记录用户明确给出的低频身体指标:体重(weight, kg) 或体脂(body_fat, %)。'
      '这是写入工具,只在用户明确要求"记录/录入/保存"且给出数值时使用;'
      '不要凭推测补数值。date_iso 可选,默认今天;body_fat 的 value 可传 18.5 表示 18.5%。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'required': <String>['kind', 'value'],
    'properties': <String, Object?>{
      'kind': <String, Object?>{
        'type': 'string',
        'enum': <String>['weight', 'body_fat'],
      },
      'value': <String, Object?>{'type': 'number', 'exclusiveMinimum': 0},
      'date_iso': <String, Object?>{
        'type': 'string',
        'description': '可选,YYYY-MM-DD 或 ISO-8601。默认今天。',
      },
      'note': <String, Object?>{'type': 'string'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final kind = _parseKind(input['kind']);
    if (kind == null) {
      return _badRequest("kind must be 'weight' or 'body_fat'");
    }
    final rawValue = input['value'];
    if (rawValue is! num || !rawValue.toDouble().isFinite || rawValue <= 0) {
      return _badRequest('value must be a positive number');
    }
    if (kind == HealthMetricKind.bodyFat && rawValue > 100) {
      return _badRequest('body_fat value must be <= 100 percent');
    }
    final capturedAt = _parseDate(input['date_iso']);
    if (capturedAt == null) {
      return _badRequest('date_iso must be a valid date when provided');
    }

    final service = await ctx.ref.read(healthMetricWriteServiceProvider.future);
    final metric = await service.recordBodyMeasurement(
      kind: kind,
      value: rawValue.toDouble(),
      capturedAt: capturedAt,
      source: 'ai',
      note: (input['note'] as String?)?.trim(),
    );
    return <String, Object?>{
      'ok': true,
      'id': metric.id,
      'kind': metric.kind.wire,
      'value': metric.value,
      'unit': metric.unit,
      'captured_at': metric.capturedAt.toUtc().toIso8601String(),
      'source': metric.sourceDevice,
    };
  }

  static HealthMetricKind? _parseKind(Object? raw) {
    final s = raw?.toString().trim();
    return switch (s) {
      'weight' => HealthMetricKind.weight,
      'body_fat' => HealthMetricKind.bodyFat,
      _ => null,
    };
  }

  static DateTime? _parseDate(Object? raw) {
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) return _dayAnchor(DateTime.now());
    final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (dateOnly != null) {
      final year = int.parse(dateOnly.group(1)!);
      final month = int.parse(dateOnly.group(2)!);
      final day = int.parse(dateOnly.group(3)!);
      final parsed = DateTime.utc(year, month, day, 12);
      if (parsed.year != year || parsed.month != month || parsed.day != day) {
        return null;
      }
      return parsed;
    }
    return DateTime.tryParse(s)?.toUtc();
  }

  static DateTime _dayAnchor(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day, 12);

  static Map<String, Object?> _badRequest(String message) => <String, Object?>{
    'error': message,
    'code': 'bad_request',
  };
}
