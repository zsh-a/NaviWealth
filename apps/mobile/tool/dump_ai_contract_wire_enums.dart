import 'dart:convert';
import 'dart:io';

import 'package:naviwealth/core/ai/contracts/ai_privacy_mode.dart';
import 'package:naviwealth/core/ai/contracts/ai_span.dart';
import 'package:naviwealth/core/ai/contracts/ai_trace.dart';
import 'package:naviwealth/core/ai/contracts/base_context.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/contracts/privacy_budget.dart';
import 'package:naviwealth/core/ai/contracts/scoped_disclosure.dart';
import 'package:naviwealth/core/ai/contracts/task_context.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/contracts/user_profile.dart';

void main() {
  final manifest = <String, List<String>>{
    'Access': Access.values.map((v) => v.wire).toList(growable: false),
    'AiPrivacyMode': AiPrivacyMode.values
        .map((v) => v.wire)
        .toList(growable: false),
    'AiSpanKind': AiSpanKind.values.map((v) => v.wire).toList(growable: false),
    'AiSpanStatus': AiSpanStatus.values
        .map((v) => v.wire)
        .toList(growable: false),
    'Backend': Backend.values.map((v) => v.wire).toList(growable: false),
    'BudgetTier': BudgetTier.values.map((v) => v.wire).toList(growable: false),
    'Capability': Capability.values.map((v) => v.wire).toList(growable: false),
    'CashflowTrend': CashflowTrend.values
        .map((v) => v.wire)
        .toList(growable: false),
    'Confirmation': Confirmation.values
        .map((v) => v.wire)
        .toList(growable: false),
    'DisclosurePurpose': DisclosurePurpose.values
        .map((v) => v.wire)
        .toList(growable: false),
    'MemoryKind': MemoryKind.values.map((v) => v.wire).toList(growable: false),
    'RiskAppetite': RiskAppetite.values
        .map((v) => v.wire)
        .toList(growable: false),
    'RiskLevel': RiskLevel.values.map((v) => v.wire).toList(growable: false),
    'RiskPreference': RiskPreference.values
        .map((v) => v.wire)
        .toList(growable: false),
    'SideEffect': SideEffect.values.map((v) => v.wire).toList(growable: false),
    'SideEffectScope': SideEffectScope.values
        .map((v) => v.wire)
        .toList(growable: false),
    'SignalKind': SignalKind.values.map((v) => v.wire).toList(growable: false),
    'SignalSeverity': SignalSeverity.values
        .map((v) => v.wire)
        .toList(growable: false),
    'TerminalReason': TerminalReason.values
        .map((v) => v.wire)
        .toList(growable: false),
  };

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(manifest));
}
