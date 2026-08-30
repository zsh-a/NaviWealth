/// `propose_capture` creates a user-confirmed Note or Decision proposal.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../domain/knowledge_models.dart';
import '../domain/knowledge_source_url.dart';
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
      'options': <String, Object?>{
        'type': 'array',
        'minItems': 1,
        'maxItems': 3,
        'items': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'label': <String, Object?>{'type': 'string'},
            'rationale': <String, Object?>{'type': 'string'},
          },
          'required': <String>['label'],
        },
      },
      'selected_label': <String, Object?>{'type': 'string'},
      'tags': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'source_url': <String, Object?>{'type': 'string'},
    },
    'required': <String>['kind', 'title'],
    'allOf': <Object?>[
      <String, Object?>{
        'if': <String, Object?>{
          'properties': <String, Object?>{
            'kind': <String, Object?>{'const': 'decision'},
          },
        },
        'then': <String, Object?>{
          'required': <String>['options', 'selected_label'],
        },
      },
    ],
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
    final rawOptions = input['options'];
    if (rawOptions != null &&
        (rawOptions is! List<Object?> ||
            rawOptions.any((raw) {
              if (raw is! Map<Object?, Object?>) return true;
              return raw['label'] is! String ||
                  (raw['rationale'] != null && raw['rationale'] is! String);
            }))) {
      return badRequest('options 必须是包含 label 和可选 rationale 的对象列表。');
    }
    final options = canonicalizeDecisionOptions(
      rawOptions is List<Object?>
          ? rawOptions.whereType<Map<Object?, Object?>>().map(
              (raw) => DecisionOption(
                label: raw['label']! as String,
                rationale: raw['rationale'] as String?,
              ),
            )
          : const <DecisionOption>[],
    );
    if (kind == 'decision' &&
        !hasValidDecisionOptions(
          options,
          selectedLabel: selected,
          maxOptions: 3,
        )) {
      return badRequest(
        'Decision 需要互不重复的 options，且 selected_label 必须对应其中一个选项。',
      );
    }
    final tags = input['tags'] is List
        ? (input['tags'] as List<Object?>)
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    final sourceInput = (input['source_url'] as String?)?.trim() ?? '';
    final sourceUrl = sourceInput.isEmpty
        ? null
        : normalizeKnowledgeSourceUrl(sourceInput);
    if (kind == 'note' && sourceInput.isNotEmpty && sourceUrl == null) {
      return badRequest('source_url 只支持安全的 HTTP(S) 链接。');
    }
    return proposalEnvelope(
      kind: 'knowledge_capture',
      summaryZh: kind == 'decision' ? '记录决策：$title' : '保存笔记：$title',
      payload: <String, Object?>{
        'entity_type': kind,
        'title': title,
        'body': body,
        if (selected.isNotEmpty) 'selected_label': selected,
        if (options.isNotEmpty)
          'options': options.map((option) => option.toJson()).toList(),
        'tags': tags,
        'source_url': ?sourceUrl,
      },
      note: '用户确认后写入；取消不会产生任何数据。',
    );
  }
}
