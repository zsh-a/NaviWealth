/// Collapsible JSON tree — the Opik-style Input / Output panel.
///
/// Renders an already-decoded JSON value (Map / List / scalar) as an
/// expandable tree with a copy-to-clipboard affordance. Used by the
/// span detail panel on the AI transparency page so a debugger can
/// inspect exactly what the model passed a tool and what came back.
///
/// Monospace body via [AiType], tone via
/// [AiTone], no ad-hoc colours. Maps/Lists collapse below a small
/// size so a 200-row tool result doesn't blow the viewport.
library;

import 'package:flutter/services.dart';
import '../../../design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'ai_motion.dart';
import 'ai_tone.dart';
import 'ai_typography.dart';

class AiJsonView extends StatelessWidget {
  const AiJsonView({super.key, required this.value, this.label});

  /// Decoded JSON: `Map`, `List`, `String`, `num`, `bool`, or `null`.
  final Object? value;

  /// Optional caption shown above the tree with a copy button.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (label != null)
              Expanded(
                child: Text(
                  label!,
                  style: AiType.meta(
                    context,
                  ).copyWith(color: AiTone.muted(context)),
                ),
              )
            else
              const Spacer(),
            FTappable(
              onPress: () =>
                  Clipboard.setData(ClipboardData(text: _pretty(value))),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Icon(
                  FLucideIcons.copy,
                  size: 14,
                  color: AiTone.muted(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s10),
          decoration: BoxDecoration(
            color: AiTone.surfaceTint(context).withValues(alpha: AppOpacity.disabled),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: _JsonNode(value: value, depth: 0, propertyKey: null),
        ),
      ],
    );
  }
}

/// One node. Maps/Lists are expandable; scalars render inline. Auto-
/// expands the root and any small collection so the common case (a
/// handful of tool args) needs no taps.
class _JsonNode extends StatefulWidget {
  const _JsonNode({
    required this.value,
    required this.depth,
    required this.propertyKey,
  });

  final Object? value;
  final int depth;
  final String? propertyKey;

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool _expanded = _autoExpand;

  bool get _autoExpand {
    final v = widget.value;
    if (widget.depth == 0) return true;
    if (v is Map) return v.length <= 6 && widget.depth < 2;
    if (v is List) return v.length <= 6 && widget.depth < 2;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final keyPrefix = widget.propertyKey;
    if (v is Map) {
      return _collection(
        context,
        open: '{',
        close: '}',
        count: v.length,
        children: [
          for (final e in v.entries)
            _JsonNode(
              value: e.value,
              depth: widget.depth + 1,
              propertyKey: '${e.key}',
            ),
        ],
      );
    }
    if (v is List) {
      return _collection(
        context,
        open: '[',
        close: ']',
        count: v.length,
        children: [
          for (var i = 0; i < v.length; i++)
            _JsonNode(value: v[i], depth: widget.depth + 1, propertyKey: '$i'),
        ],
      );
    }
    // Scalar leaf.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: RichText(
        text: TextSpan(
          style: _mono(context),
          children: [
            if (keyPrefix != null)
              TextSpan(
                text: '$keyPrefix: ',
                style: _mono(context).copyWith(color: AiTone.muted(context)),
              ),
            TextSpan(text: _scalar(v), style: _scalarStyle(context, v)),
          ],
        ),
      ),
    );
  }

  Widget _collection(
    BuildContext context, {
    required String open,
    required String close,
    required int count,
    required List<Widget> children,
  }) {
    final keyPrefix = widget.propertyKey;
    final header = FTappable(
      onPress: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _expanded ? FLucideIcons.chevronDown : FLucideIcons.chevronRight,
              size: 13,
              color: AiTone.muted(context),
            ),
            const SizedBox(width: AppSpacing.s2),
            Flexible(
              child: Text.rich(
                TextSpan(
                  style: _mono(context),
                  children: [
                    if (keyPrefix != null)
                      TextSpan(
                        text: '$keyPrefix: ',
                        style: _mono(
                          context,
                        ).copyWith(color: AiTone.muted(context)),
                      ),
                    TextSpan(
                      text: _expanded ? open : '$open … $close',
                      style: _mono(
                        context,
                      ).copyWith(color: AiTone.muted(context)),
                    ),
                    TextSpan(
                      text: '  $count',
                      style: AiType.meta(
                        context,
                      ).copyWith(color: AiTone.muted(context)),
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        AnimatedSize(
          duration: AiMotion.short,
          curve: AiMotion.standard,
          alignment: Alignment.topLeft,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.s14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...children,
                      Text(
                        close,
                        style: _mono(
                          context,
                        ).copyWith(color: AiTone.muted(context)),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  TextStyle _mono(BuildContext context) =>
      AiType.meta(context).copyWith(fontFamily: 'monospace');

  TextStyle _scalarStyle(BuildContext context, Object? v) {
    final base = _mono(context);
    if (v == null) return base.copyWith(color: AiTone.muted(context));
    if (v is num || v is bool) {
      return base.copyWith(color: AiTone.active(context));
    }
    return base.copyWith(color: AiTone.onSurface(context));
  }

  String _scalar(Object? v) {
    if (v == null) return 'null';
    if (v is String) return '"$v"';
    return '$v';
  }
}

String _pretty(Object? v) {
  final buf = StringBuffer();
  _write(buf, v, 0);
  return buf.toString();
}

void _write(StringBuffer b, Object? v, int indent) {
  final pad = '  ' * indent;
  final pad1 = '  ' * (indent + 1);
  if (v is Map) {
    if (v.isEmpty) {
      b.write('{}');
      return;
    }
    b.write('{\n');
    final entries = v.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      b.write('$pad1"${entries[i].key}": ');
      _write(b, entries[i].value, indent + 1);
      b.write(i == entries.length - 1 ? '\n' : ',\n');
    }
    b.write('$pad}');
  } else if (v is List) {
    if (v.isEmpty) {
      b.write('[]');
      return;
    }
    b.write('[\n');
    for (var i = 0; i < v.length; i++) {
      b.write(pad1);
      _write(b, v[i], indent + 1);
      b.write(i == v.length - 1 ? '\n' : ',\n');
    }
    b.write('$pad]');
  } else if (v is String) {
    b.write('"$v"');
  } else {
    b.write('$v');
  }
}
