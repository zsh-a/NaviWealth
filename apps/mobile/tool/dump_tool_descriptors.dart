import 'dart:convert';
import 'dart:io';

import 'package:naviwealth/app/tool_descriptor_catalog.dart';

void main() {
  final descriptors = allToolDescriptors.map((d) => d.toJson()).toList()
    ..sort((a, b) => (a['name']! as String).compareTo(b['name']! as String));
  const encoder = JsonEncoder.withIndent('  ');
  stdout.writeln(encoder.convert(descriptors));
}
