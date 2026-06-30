library;

import 'dart:convert';

import 'frb_chat_types.dart';

typedef FrbChatToolLineHandler = Future<String> Function(String line);

class FrbChatToolDispatcher {
  const FrbChatToolDispatcher({required FrbChatToolLineHandler handler})
    : _handler = handler;

  final FrbChatToolLineHandler _handler;

  Future<FrbToolResult> call(FrbToolCall call) async {
    try {
      final line = jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': call.id,
        'method': 'tool.call',
        'params': <String, Object?>{
          'name': call.name,
          'input': call.input ?? const <String, Object?>{},
        },
      });
      final response = frbObject(jsonDecode(await _handler(line)));
      final error = response['error'];
      if (error != null) {
        return FrbToolResult(
          id: call.id,
          name: call.name,
          output: error,
          isError: true,
        );
      }
      return FrbToolResult(
        id: call.id,
        name: call.name,
        output: response['result'],
      );
    } catch (error) {
      return FrbToolResult(
        id: call.id,
        name: call.name,
        output: <String, Object?>{
          'code': 'frb_chat_tool_dispatch_failed',
          'message': error.toString(),
        },
        isError: true,
      );
    }
  }
}
