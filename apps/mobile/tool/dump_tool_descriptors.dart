import 'dart:convert';
import 'dart:io';

import 'package:naviwealth/core/ai/contracts/contracts.dart';

void main() {
  final descriptors = allToolDescriptors.map((d) => d.toJson()).toList()
    ..sort((a, b) => (a['name']! as String).compareTo(b['name']! as String));
  const encoder = JsonEncoder.withIndent('  ');
  stdout.writeln(encoder.convert(descriptors));
}
