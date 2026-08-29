/// `propose_capture` creates a user-confirmed Note or Decision proposal.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '_tool_support.dart';

class ProposeCaptureTool implements DeviceTool {
  const ProposeCaptureTool();

  @override
  String get name => 'propose_capture';

  @override
  String get description =>
      '把内容保存为 Note，或在用户明确表达已做选择时保存为 Decision。'
      '只返回待确认方案，不直接写入。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'kind': <String, Object?>{
        'type': 'string',
        'enum': <String>['note', 'decision'],
      },
      'title': <String, Object?>{'type': 'string'},
      'body': <String, Object?>{'type': 'string'},
      'selected_label': <String, Object?>{'type': 'string'},
      'tags': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'source_url': <String, Object?>{'type': 'string'},
    },
    'required': <String>['kind', 'title'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final kind = (input['kind'] as String?)?.trim() ?? '';
    final title = (input['title'] as String?)?.trim() ?? '';
    final body = (input['body'] as String?)?.trim() ?? '';
    final selected = (input['selected_label'] as String?)?.trim() ?? '';
    if (!const <String>{'note', 'decision'}.contains(kind)) {
      return badRequest('kind 只支持 note / decision。');
    }
    if (title.isEmpty) return badRequest('title 必填。');
    if (kind == 'decision' && selected.isEmpty) {
      return badRequest('Decision 需要 selected_label。');
    }
    final tags = input['tags'] is List
        ? (input['tags'] as List<Object?>)
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    return proposalEnvelope(
      kind: 'knowledge_capture',
      summaryZh: kind == 'decision' ? '记录决策：$title' : '保存笔记：$title',
      payload: <String, Object?>{
        'entity_type': kind,
        'title': title,
        'body': body,
        if (selected.isNotEmpty) 'selected_label': selected,
        'tags': tags,
        if ((input['source_url'] as String?)?.trim().isNotEmpty ?? false)
          'source_url': (input['source_url'] as String).trim(),
      },
      note: '用户确认后写入；取消不会产生任何数据。',
    );
  }
}
