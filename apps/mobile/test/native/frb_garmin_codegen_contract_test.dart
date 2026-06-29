import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FRB generated bindings expose the Garmin health bridge', () {
    final agentRuntimeFacade = File(
      'lib/src/rust/api/agent_runtime.dart',
    ).readAsStringSync();
    final dartFacade = File('lib/src/rust/api/health.dart').readAsStringSync();
    final dartBindings = File(
      'lib/src/rust/frb_generated.dart',
    ).readAsStringSync();
    final dartIoBindings = File(
      'lib/src/rust/frb_generated.io.dart',
    ).readAsStringSync();
    final dartWebBindings = File(
      'lib/src/rust/frb_generated.web.dart',
    ).readAsStringSync();
    final rustBindings = File(
      'native/lifeos_native/src/frb_generated.rs',
    ).readAsStringSync();

    for (final symbol in _agentRuntimeFacadeSymbols) {
      expect(
        agentRuntimeFacade,
        contains(symbol),
        reason: 'Agent runtime facade: $symbol',
      );
    }
    for (final symbol in _dartFacadeSymbols) {
      expect(dartFacade, contains(symbol), reason: 'Dart facade: $symbol');
    }
    for (final symbol in _dartGeneratedApiSymbols) {
      expect(dartBindings, contains(symbol), reason: 'Dart FRB: $symbol');
    }
    for (final symbol in _dartCodecSymbols) {
      expect(dartIoBindings, contains(symbol), reason: 'Dart IO FRB: $symbol');
      expect(
        dartWebBindings,
        contains(symbol),
        reason: 'Dart Web FRB: $symbol',
      );
    }
    for (final symbol in _rustGeneratedSymbols) {
      expect(rustBindings, contains(symbol), reason: 'Rust FRB: $symbol');
    }
  });
}

const _dartFacadeSymbols = <String>[
  'garminInit',
  'garminAuthenticate',
  'garminSubmitMfa',
  'garminAuthState',
  'garminSyncRange',
  'garminSyncRangeStream',
  'garminSyncCancel',
  'garminSyncCursors',
  'garminLogout',
  'garminExportSession',
  'GarminSyncProgress',
];

const _agentRuntimeFacadeSymbols = <String>[
  'agentRuntimeProtocolVersion',
  'agentRuntimeCatalogVersion',
  'agentRuntimeCatalogSummary',
  'agentRuntimeStartRunStep',
  'agentRuntimeContinueRunStep',
  'agentRuntimeValidateRunRequest',
  'agentRuntimeValidateTrace',
  'agentRuntimeValidateToolSpec',
];

const _dartGeneratedApiSymbols = <String>[
  'crateApiAgentRuntimeAgentRuntimeProtocolVersion',
  'crateApiAgentRuntimeAgentRuntimeCatalogVersion',
  'crateApiAgentRuntimeAgentRuntimeCatalogSummary',
  'crateApiAgentRuntimeAgentRuntimeStartRunStep',
  'crateApiAgentRuntimeAgentRuntimeContinueRunStep',
  'crateApiAgentRuntimeAgentRuntimeValidateRunRequest',
  'crateApiAgentRuntimeAgentRuntimeValidateTrace',
  'crateApiAgentRuntimeAgentRuntimeValidateToolSpec',
  'crateApiHealthGarminInit',
  'crateApiHealthGarminAuthenticate',
  'crateApiHealthGarminSubmitMfa',
  'crateApiHealthGarminAuthState',
  'crateApiHealthGarminSyncRange',
  'crateApiHealthGarminSyncRangeStream',
  'crateApiHealthGarminSyncCancel',
  'crateApiHealthGarminSyncCursors',
  'crateApiHealthGarminLogout',
  'crateApiHealthGarminExportSession',
];

const _dartCodecSymbols = <String>[
  'GarminSyncProgress',
  'dco_decode_garmin_sync_progress',
  'sse_decode_garmin_sync_progress',
  'sse_encode_garmin_sync_progress',
];

const _rustGeneratedSymbols = <String>[
  'wire__crate__api__agent_runtime__agent_runtime_protocol_version_impl',
  'wire__crate__api__agent_runtime__agent_runtime_catalog_version_impl',
  'wire__crate__api__agent_runtime__agent_runtime_catalog_summary_impl',
  'wire__crate__api__agent_runtime__agent_runtime_start_run_step_impl',
  'wire__crate__api__agent_runtime__agent_runtime_continue_run_step_impl',
  'wire__crate__api__agent_runtime__agent_runtime_validate_run_request_impl',
  'wire__crate__api__agent_runtime__agent_runtime_validate_trace_impl',
  'wire__crate__api__agent_runtime__agent_runtime_validate_tool_spec_impl',
  'wire__crate__api__health__garmin_init_impl',
  'wire__crate__api__health__garmin_authenticate_impl',
  'wire__crate__api__health__garmin_submit_mfa_impl',
  'wire__crate__api__health__garmin_auth_state_impl',
  'wire__crate__api__health__garmin_sync_range_impl',
  'wire__crate__api__health__garmin_sync_range_stream_impl',
  'wire__crate__api__health__garmin_sync_cancel_impl',
  'wire__crate__api__health__garmin_sync_cursors_impl',
  'wire__crate__api__health__garmin_logout_impl',
  'wire__crate__api__health__garmin_export_session_impl',
  'crate::api::health::GarminSyncProgress',
];
