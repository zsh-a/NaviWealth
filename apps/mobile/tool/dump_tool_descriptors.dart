import 'dart:convert';
import 'dart:io';

import 'package:naviwealth/app/production_ai_catalog.dart';

void main() {
  final descriptors =
      productionToolDescriptors.values.map((d) => d.toJson()).toList()..sort(
        (a, b) => (a['name']! as String).compareTo(b['name']! as String),
      );
  const encoder = JsonEncoder.withIndent('  ');
  stdout.writeln(encoder.convert(descriptors));
}
