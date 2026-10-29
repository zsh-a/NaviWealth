/// Stable presentation keys for errors emitted by the device AI runtime.
///
/// Runtime/provider details stay in the local trace. Chat history stores only
/// a small, non-sensitive key for errors that have a known repair path, so
/// the timeline can explain the next action without exposing provider wire
/// responses or API diagnostics as user-facing copy.
library;

const String kChatErrorDeviceUnavailable = 'device_unavailable';
const String kChatErrorAuthentication = 'chat_error_authentication';
const String kChatErrorEndpoint = 'chat_error_endpoint';
const String kChatErrorRateLimited = 'chat_error_rate_limited';
const String kChatErrorRequest = 'chat_error_request';
const String kChatErrorNetwork = 'chat_error_network';
const String kChatErrorFirstResponseTimeout =
    'chat_error_first_response_timeout';
const String kChatErrorReadIdleTimeout = 'chat_error_read_idle_timeout';
const String kChatErrorModelProgressTimeout =
    'chat_error_model_progress_timeout';
const String kChatErrorTotalTimeout = 'chat_error_total_timeout';
const String kChatErrorRuntime = 'chat_error_runtime';

/// Converts known runtime/provider codes to a stable, localizable key.
///
/// [message] is considered only as a fallback signal because an outer FRB
/// error can occasionally wrap the original provider code in its text. The
/// raw message is returned for unknown failures so diagnostics remain visible
/// rather than being replaced with an inaccurate guess.
String chatErrorPresentationKey({String? code, required String message}) {
  final signal = '${code ?? ''} $message'.toLowerCase();
  if (signal.contains(kChatErrorDeviceUnavailable)) {
    return kChatErrorDeviceUnavailable;
  }
  if (signal.contains('rate_limited') ||
      signal.contains('rate limited') ||
      _containsHttp(signal, 429)) {
    return kChatErrorRateLimited;
  }
  if (_containsHttp(signal, 401) ||
      _containsHttp(signal, 403) ||
      signal.contains('unauthorized') ||
      signal.contains('forbidden') ||
      signal.contains('api key') ||
      signal.contains('authentication')) {
    return kChatErrorAuthentication;
  }
  if (_containsHttp(signal, 404) ||
      signal.contains('not found') ||
      signal.contains('base url')) {
    return kChatErrorEndpoint;
  }
  if (signal.contains('validation_error') ||
      signal.contains('bad_request') ||
      signal.contains('bad request') ||
      signal.contains('invalid model') ||
      _containsHttp(signal, 400)) {
    return kChatErrorRequest;
  }
  if (signal.contains('provider_first_response_timeout') ||
      signal.contains('provider_first_byte_timeout')) {
    return kChatErrorFirstResponseTimeout;
  }
  if (signal.contains('provider_read_idle_timeout')) {
    return kChatErrorReadIdleTimeout;
  }
  if (signal.contains('provider_model_progress_timeout')) {
    return kChatErrorModelProgressTimeout;
  }
  if (signal.contains('provider_total_timeout')) {
    return kChatErrorTotalTimeout;
  }
  if (signal.contains('timeout') ||
      signal.contains('timed out') ||
      signal.contains('timed_out') ||
      signal.contains('provider_request_failed') ||
      signal.contains('provider_body_read_failed') ||
      signal.contains('provider_stream_read_failed') ||
      signal.contains('error sending request') ||
      signal.contains('bad gateway') ||
      signal.contains('network') ||
      signal.contains('transport') ||
      signal.contains('connection') ||
      signal.contains('dns') ||
      signal.contains('tls') ||
      signal.contains('provider_http_5') ||
      [500, 502, 503, 504].any((status) => _containsHttp(signal, status))) {
    return kChatErrorNetwork;
  }
  if (signal.contains('internal_error') ||
      signal.contains('provider_decode_failed') ||
      signal.contains('frb_')) {
    return kChatErrorRuntime;
  }
  return message;
}

bool isChatConfigurationError(String? key) => switch (key) {
  kChatErrorDeviceUnavailable ||
  kChatErrorAuthentication ||
  kChatErrorEndpoint ||
  kChatErrorRequest => true,
  _ => false,
};

bool isChatTimeoutError(String? key) => switch (key) {
  kChatErrorFirstResponseTimeout ||
  kChatErrorReadIdleTimeout ||
  kChatErrorModelProgressTimeout ||
  kChatErrorTotalTimeout => true,
  _ => false,
};

bool _containsHttp(String signal, int status) =>
    signal.contains('provider_http_$status') || signal.contains('http $status');
