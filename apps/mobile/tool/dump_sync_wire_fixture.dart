import 'dart:convert';
import 'dart:io';

import 'package:naviwealth/core/sync/sync_api_client.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dump_sync_wire_fixture <fixture-name>');
    exitCode = 64;
    return;
  }

  final change = switch (args.single) {
    'sync_v2_client_push_row_change' => const RowChange(
      table: 'fin:accounts',
      id: 'acc-1',
      payload: <String, Object?>{
        'id': 'acc-1',
        'name': 'Cash',
        'hlc': '1716381000123.0000-device-a',
        'deleted_at': null,
      },
      version: '1716381000123.0000-device-a',
      deleted: false,
    ),
    final unknown => _unknown(unknown),
  };

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(change.toJson()));
}

Never _unknown(String name) {
  stderr.writeln('unknown sync wire fixture: $name');
  exit(64);
}
