/// One-tap connectivity probe for an [LlmProfile].
///
/// Fires a **minimal real request** down the *exact* provider path the
/// device runtime uses so a green result means "this key + endpoint +
/// model actually work", not just "the host pings". The probe is
/// independent of the active selection and opt-in state — it can test a
/// profile the user is still editing and hasn't saved.
library;

import 'llm_credentials.dart';

enum LlmProbeStatus {
  /// Provider answered 2xx — key, endpoint and model all accepted.
  ok,

  /// Reached the provider, but the key was rejected (401 / 403).
  authFailed,

  /// Endpoint not found (404) — usually a wrong Base URL.
  notFound,

  /// Reached and authenticated, but rate-limited (429). Connectivity
  /// is proven; the user just needs to retry later.
  rateLimited,

  /// Provider understood the request but rejected it (400) — e.g. an
  /// unknown model name. Carries the provider's own message.
  badRequest,

  /// Could not reach the provider at all (DNS / TLS / timeout / CORS).
  network,

  /// Anything else (unexpected status, malformed body).
  unknown,
}

class LlmProbeResult {
  const LlmProbeResult(this.status, this.message, {this.httpStatus});

  final LlmProbeStatus status;

  /// Short zh message safe to surface in a toast / inline line.
  final String message;
  final int? httpStatus;

  bool get ok => status == LlmProbeStatus.ok;

  /// True when the provider actually answered (so the network path +
  /// usually auth are fine) even if the call itself didn't 2xx.
  bool get reachedProvider =>
      status == LlmProbeStatus.ok ||
      status == LlmProbeStatus.rateLimited ||
      status == LlmProbeStatus.badRequest ||
      status == LlmProbeStatus.authFailed ||
      status == LlmProbeStatus.notFound;
}

abstract class LlmConnectivityProbe {
  const LlmConnectivityProbe();

  Future<LlmProbeResult> probe(
    LlmProfile profile, {
    Duration timeout = const Duration(seconds: 20),
  });
}

class UnavailableLlmConnectivityProbe implements LlmConnectivityProbe {
  const UnavailableLlmConnectivityProbe();

  @override
  Future<LlmProbeResult> probe(
    LlmProfile profile, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    return const LlmProbeResult(LlmProbeStatus.unknown, 'AI 运行时尚未初始化，请稍后重试');
  }
}

/// Minimal provider failure shape used by connectivity UX.
///
/// Kept in the credentials seam so app/settings code does not import the
/// low-level direct-Dart provider clients merely to classify FRB errors.
class LlmProbeException implements Exception {
  const LlmProbeException({required this.statusCode, required this.message});

  final int statusCode;
  final String message;

  @override
  String toString() => 'LlmProbeException($statusCode): $message';
}

/// Pure mapping HTTP failure → user-facing probe result. Top-level so
/// it's unit-testable without a network.
LlmProbeResult classifyLlmProbeException(LlmProbeException e) {
  return classifyLlmProbeFailure(
    statusCode: e.statusCode,
    message: e.message,
  );
}

LlmProbeResult classifyLlmProbeFailure({
  required int statusCode,
  required String message,
}) {
  final s = statusCode;
  return switch (s) {
    0 => LlmProbeResult(
      LlmProbeStatus.network,
      '无法连接 · 检查网络或 Base URL（$message）',
    ),
    401 || 403 => LlmProbeResult(
      LlmProbeStatus.authFailed,
      '鉴权失败 · API Key 无效或无权限',
      httpStatus: s,
    ),
    404 => LlmProbeResult(
      LlmProbeStatus.notFound,
      '端点不存在 · 检查 Base URL（404）',
      httpStatus: s,
    ),
    429 => LlmProbeResult(
      LlmProbeStatus.rateLimited,
      '已连通，但被限流（429）· Key 有效',
      httpStatus: s,
    ),
    400 => LlmProbeResult(
      LlmProbeStatus.badRequest,
      '已连通，但请求被拒（400）· 多为模型名无效：$message',
      httpStatus: s,
    ),
    _ => LlmProbeResult(
      LlmProbeStatus.unknown,
      '测试失败（HTTP $s）：$message',
      httpStatus: s,
    ),
  };
}
