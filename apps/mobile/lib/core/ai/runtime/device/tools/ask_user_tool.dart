/// `ask_user` — structured decision-point tool (shell, cross-domain).
///
/// The Claude-Code / Codex interaction pattern: when the model reaches a
/// high-impact or genuinely ambiguous fork it should NOT guess and keep
/// going, nor bury the options in prose. It calls `ask_user` with a typed
/// [DecisionRequest]; the runtime treats this as a **terminal** action, the
/// Host renders the options as an interactive card, and the user's pick is
/// written back as the next turn's input. This replaces the old "parse a
/// markdown menu out of free text" heuristic with a first-class, extensible
/// contract.
///
/// `invoke` validates + normalises the request and echoes it back as the
/// tool result — that echoed value is both the loop's `tool_result` and
/// the payload the UI ([DecisionRequest.tryParse]) renders.
library;

import 'package:uuid/uuid.dart';

import '../../../contracts/interaction.dart';
import '../../../contracts/tool_descriptor.dart' show kDomainShell;
import 'device_tool.dart';

/// Wire tool name — referenced by the runtime terminal-tool check.
const String kAskUserToolName = 'ask_user';
const Uuid _interactionUuid = Uuid();

class AskUserTool implements DeviceTool {
  const AskUserTool();

  @override
  String get name => kAskUserToolName;

  @override
  String get description =>
      '在遇到高影响 / 不可逆 / 有多条合理路线的决策点时调用,把选择交给用户而不是自己拍板。'
      '适用:架构与技术选型、引入新依赖、改数据模型 / 同步协议 / 安全边界、目录结构大改、'
      '或任何"有 2~4 种都说得通的做法"的岔路。'
      '传入 title(决策标题)、context(背景一句话)、options(2~4 个,每个含 id/label/description'
      '/pros/cons,可标 recommended:true)、可选 allow_custom。'
      '调用后请**停下来等用户选择**,不要自答或继续调用其它工具。'
      '日常无歧义的小操作不要用本工具,直接做或用 propose_* 即可。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': '决策标题,如"状态管理方案选择"。'},
      'context': {'type': 'string', 'description': '一句话背景,说明为什么要做这个选择。'},
      'options': {
        'type': 'array',
        'minItems': 2,
        'maxItems': 4,
        'items': <String, Object?>{
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
            'label': {'type': 'string', 'description': '简短选项名。'},
            'description': {'type': 'string'},
            'pros': {
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'cons': {
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'recommended': {'type': 'boolean'},
          },
          'required': <String>['label'],
        },
      },
      'allow_custom': {
        'type': 'boolean',
        'description': '是否允许用户给出自定义方案,默认 true。',
      },
    },
    'required': <String>['title', 'options'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final title = (input['title'] as String?)?.trim() ?? '';
    final rawOptions = input['options'];
    if (title.isEmpty || rawOptions is! List) {
      return _bad('title 必填,options 必须是数组。');
    }

    final options = <Map<String, Object?>>[];
    for (final o in rawOptions) {
      if (o is! Map) continue;
      final m = o.map((k, v) => MapEntry(k.toString(), v));
      final label = (m['label'] as String?)?.trim();
      if (label == null || label.isEmpty) continue;
      options.add(<String, Object?>{
        'id': (m['id'] as String?)?.trim().isNotEmpty == true
            ? (m['id'] as String).trim()
            : label,
        'label': label,
        'description': (m['description'] as String?)?.trim() ?? '',
        'pros': _stringList(m['pros']),
        'cons': _stringList(m['cons']),
        'recommended': m['recommended'] == true,
      });
    }
    if (options.length < 2) {
      return _bad('至少需要 2 个有效 options(每个含非空 label)。');
    }
    if (options.length > 4) {
      return _bad('options 最多 4 个。');
    }

    final allowCustom = input['allow_custom'] != false;
    final interaction = AiInteractionEnvelope(
      interactionId: 'interaction_${_interactionUuid.v4()}',
      kind: AiInteractionKind.choice,
      mode: AiInteractionMode.oneTap,
      status: AiInteractionStatus.pending,
      title: title,
      prompt: (input['context'] as String?)?.trim() ?? '',
      options: [
        for (final option in options)
          AiInteractionOption(
            id: option['id']! as String,
            label: option['label']! as String,
            description: option['description']! as String,
            metadata: <String, Object?>{
              'pros': option['pros'],
              'cons': option['cons'],
              'recommended': option['recommended'],
            },
          ),
      ],
      responseSchema: const <String, Object?>{
        'type': 'object',
        'required': <String>['option_id'],
        'properties': <String, Object?>{
          'option_id': <String, Object?>{'type': 'string'},
          'custom_text': <String, Object?>{'type': 'string'},
        },
      },
      payload: <String, Object?>{'domain': kDomainShell},
      metadata: <String, Object?>{'allow_custom': allowCustom},
      resumeKind: AiInteractionResumeKind.chatTurn,
      createdAt: DateTime.now().toUtc(),
    );

    // Keep the legacy fields during migration so existing decision cards
    // render unchanged; `interaction` is the durable runtime contract.
    return <String, Object?>{
      'type': 'decision_request',
      'title': title,
      'context': (input['context'] as String?)?.trim() ?? '',
      'options': options,
      'allow_custom': allowCustom,
      // The loop pauses here; the user's pick arrives as the next turn.
      'awaiting_user': true,
      'domain': kDomainShell,
      'interaction': interaction.toJson(),
    };
  }

  static List<String> _stringList(Object? v) => v is List
      ? v
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
      : const <String>[];

  static Map<String, Object?> _bad(String msg) => <String, Object?>{
    'error': msg,
    'code': 'bad_request',
  };
}
