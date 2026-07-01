import 'dart:convert';
import 'dart:io';

import 'package:naviwealth/app/agent_runtime/agent_runtime_headless_tool_host.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_tool_host.dart';

/// Headless app-backed process entry for the Rust `--tool-host` bridge.
///
/// Runs without UI, but mounts the production domain tool graph in a
/// ProviderContainer with mock preferences and an in-memory Drift database.
/// Use through Flutter's runner, for example:
///
/// `flutter pub run bin/agent_runtime_tool_host_headless.dart --domains=all`
Future<void> main(List<String> args) async {
  final domainsArg = _argValue(args, '--domains');
  AgentRuntimeHeadlessToolHost? headless;
  try {
    headless = await createAgentRuntimeHeadlessToolHost(
      domains: parseHeadlessDomains(domainsArg),
    );
    await runAgentRuntimeToolHostLines(
      host: headless.host,
      input: stdin.transform(utf8.decoder).transform(const LineSplitter()),
      output: stdout.writeln,
    );
  } on Object catch (e) {
    stderr.writeln('agent_runtime_tool_host_headless failed: $e');
    exitCode = 64;
  } finally {
    await headless?.dispose();
  }
}

String? _argValue(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}
