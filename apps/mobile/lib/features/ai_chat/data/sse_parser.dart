import 'dart:async';
import 'dart:convert';

import '../domain/chat_events.dart';

/// Parsed envelope for one SSE frame. Internal helper for [decodeSseEvents].
class _RawSseFrame {
  _RawSseFrame(this.event, this.data);
  final String event;
  final String data;
}

/// Convert a `Stream<List<int>>` of UTF-8 SSE bytes into a typed
/// `Stream<AiChatEvent>`.
///
/// The parser tolerates frames split across chunks (Cloudflare may
/// flush mid-frame). Each frame is decoded against the contract in
/// `apps/backend/src/ai/sse.rs`:
///
/// ```
/// event: <name>
/// data:  <single-line JSON>
///
/// ```
///
/// Frames whose JSON payload doesn't match the documented shape for the
/// declared event are dropped silently — surface them and a backend bump
/// would crash every client.
Stream<AiChatEvent> decodeSseEvents(Stream<List<int>> bytes) {
  return _decodeRawFrames(bytes)
      .map(_decodeFrame)
      .where((e) => e != null)
      .cast<AiChatEvent>();
}

Stream<_RawSseFrame> _decodeRawFrames(Stream<List<int>> bytes) async* {
  // Decode UTF-8 across chunk boundaries — the worker may flush partial
  // multibyte characters during long Chinese assistant text.
  final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
  String? event;
  final dataBuf = StringBuffer();

  await for (final line in lines) {
    if (line.isEmpty) {
      if (event != null) {
        yield _RawSseFrame(event, dataBuf.toString());
      }
      event = null;
      dataBuf.clear();
      continue;
    }
    // Comment line per SSE spec — used as keep-alive in some servers.
    if (line.startsWith(':')) continue;

    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      // Per SSE spec, multiple `data:` lines in one frame are joined with
      // newlines. The relay only ever emits a single data line, but we
      // honour the spec for robustness.
      final piece = line.substring(5).trimLeft();
      if (dataBuf.isNotEmpty) dataBuf.write('\n');
      dataBuf.write(piece);
    }
    // Ignore `id:` / `retry:` / unknown fields.
  }
  // Flush a trailing frame without a blank line — happens when the worker
  // closes the connection right after the final `done` frame.
  if (event != null) {
    yield _RawSseFrame(event, dataBuf.toString());
  }
}

AiChatEvent? _decodeFrame(_RawSseFrame frame) {
  Object? json;
  try {
    json = jsonDecode(frame.data);
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  final m = json.map((k, v) => MapEntry(k.toString(), v));

  switch (frame.event) {
    case 'tool_call':
      final id = m['id'];
      final name = m['name'];
      if (id is! String || name is! String) return null;
      return ToolCallEvent(id: id, name: name, input: m['input']);
    case 'tool_result':
      final id = m['id'];
      final name = m['name'];
      if (id is! String || name is! String) return null;
      return ToolResultEvent(id: id, name: name, output: m['output']);
    case 'text':
      final text = m['text'];
      if (text is! String) return null;
      return TextEvent(text);
    case 'error':
      final msg = m['message'];
      return ErrorEvent(msg is String ? msg : 'unknown error');
    case 'done':
      final stop = m['stop_reason'];
      final rounds = m['rounds'];
      return DoneEvent(
        stopReason: stop is String ? stop : 'unknown',
        rounds: rounds is int ? rounds : 0,
      );
    default:
      return null;
  }
}
