import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../domain/bcr_github_target.dart';
import 'bcr_knowledge_archive.dart';

enum BcrGithubFailureCode {
  network,
  unauthorized,
  forbidden,
  notFound,
  rateLimited,
  invalidRepository,
  invalidData,
}

class BcrGithubFailure implements Exception {
  const BcrGithubFailure(this.code, {this.retryAfter});
  final BcrGithubFailureCode code;
  final Duration? retryAfter;

  @override
  String toString() => 'BcrGithubFailure(${code.name})';
}

class BcrGithubRead {
  const BcrGithubRead({
    required this.target,
    required this.head,
    this.snapshot,
  });
  final BcrGithubTarget target;
  final String head;
  final BcrKnowledgeArchive? snapshot;
}

/// Direct, read-only GitHub transport. The caller owns the injected adapter.
/// Only that adapter is borrowed: app auth/logging interceptors, global headers
/// and query parameters must never receive or replace this repository's token.
class BcrGithubClient {
  BcrGithubClient(Dio dio)
    : _dio = Dio()
        ..httpClientAdapter = _BoundedGithubAdapter(dio.httpClientAdapter);

  static const _timeout = Duration(seconds: 25);
  static const _jsonLimit = 12 * 1024 * 1024;
  static const _fileLimit = 2 * 1024 * 1024;
  static const _blobBudget = 16 * 1024 * 1024;
  final Dio _dio;
  // Map literals retain insertion order; hits move an entry to the LRU tail.
  final _blobs = <String, ({String text, int bytes})>{};
  var _blobBytes = 0;

  Future<BcrGithubRead> read({
    required String repository,
    required String token,
    String branch = '',
    String? knownHead,
    bool hasCachedSnapshot = false,
    CancelToken? cancelToken,
  }) async {
    late final ({String owner, String repository}) identity;
    try {
      identity = BcrGithubTarget.parseRepository(repository);
      if (branch.trim().isNotEmpty && !isValidBcrGithubBranch(branch.trim())) {
        throw const FormatException('Invalid branch');
      }
    } on FormatException {
      throw const BcrGithubFailure(BcrGithubFailureCode.invalidRepository);
    }
    final credential = token.trim();
    if (credential.isEmpty ||
        credential.length > 4096 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(credential)) {
      throw const BcrGithubFailure(BcrGithubFailureCode.unauthorized);
    }
    _checkCancelled(cancelToken);
    final root =
        'https://api.github.com/repos/${identity.owner}/${identity.repository}';
    try {
      Future<Map<String, Object?>> get(String path) =>
          _request('$root$path', credential, cancelToken);
      final repo = await get('');
      if (repo['private'] is! bool) {
        throw const FormatException('Missing privacy');
      }
      if (repo['private'] != true || repo['disabled'] == true) {
        throw const BcrGithubFailure(BcrGithubFailureCode.forbidden);
      }
      final resolved = branch.trim().isEmpty
          ? repo['default_branch']
          : branch.trim();
      if (resolved is! String) throw const FormatException('Missing branch');
      final target = BcrGithubTarget(
        owner: identity.owner,
        repository: identity.repository,
        branch: resolved,
      );
      final ref = await get(
        '/git/ref/heads/${Uri.encodeComponent(target.branch)}',
      );
      final reference = _object(ref['object']);
      if (reference['type'] != null && reference['type'] != 'commit') {
        throw const FormatException('Invalid branch reference');
      }
      final head = _sha(reference['sha']);
      _checkCancelled(cancelToken);
      if (hasCachedSnapshot && knownHead == head) {
        return BcrGithubRead(target: target, head: head);
      }
      final commit = await get('/git/commits/$head');
      _checkIdentity(commit['sha'], head);
      final tree = _sha(_object(commit['tree'])['sha']);
      final listing = await get('/git/trees/$tree?recursive=1');
      _checkIdentity(listing['sha'], tree);
      final entries = listing['tree'];
      if (listing['truncated'] != false ||
          entries is! List ||
          entries.length > 100000) {
        throw const FormatException('Incomplete GitHub tree');
      }
      final texts = <({String path, String sha, int size})>[];
      final attachmentSizes = <String, int>{};
      final seen = <String>{};
      var textBytes = 0;
      var declaredBytes = 0;
      for (final value in entries) {
        final entry = _object(value);
        final path = entry['path'];
        if (path is! String) throw const FormatException('Missing Git path');
        final binary = RegExp(r'^knowledge/attachments/([a-f0-9]{64})\.bin$')
            .firstMatch(path);
        final text = isBcrKnowledgeTextPath(path);
        if (!text && binary == null) continue;
        final size = entry['size'];
        if (!seen.add(path) ||
            entry['type'] != 'blob' ||
            entry['mode'] != '100644' ||
            size is! int ||
            size < 0) {
          throw const FormatException('Unsupported GitHub file');
        }
        final blobSha = _sha(entry['sha']);
        declaredBytes += size;
        if (declaredBytes > 512 * 1024 * 1024) {
          throw const FormatException('GitHub snapshot is too large');
        }
        if (text) {
          textBytes += size;
          if (size > _fileLimit ||
              textBytes > 16 * 1024 * 1024 ||
              texts.length >= 11010) {
            throw const FormatException('GitHub text is too large');
          }
          texts.add((path: path, sha: blobSha, size: size));
        } else {
          if (size > 128 * 1024 * 1024 || attachmentSizes.length >= 10000) {
            throw const FormatException('GitHub attachments are too large');
          }
          attachmentSizes[binary!.group(1)!] = size;
        }
      }
      final files = <String, String>{};
      for (var start = 0; start < texts.length; start += 4) {
        final end = (start + 4).clamp(0, texts.length);
        await Future.wait(
          texts.sublist(start, end).map((entry) async {
            final cached = _cachedBlob(entry.sha, entry.size);
            if (cached != null) {
              files[entry.path] = cached;
              return;
            }
            final blob = await get('/git/blobs/${entry.sha}');
            _checkIdentity(blob['sha'], entry.sha);
            final encoded = blob['content'];
            if (blob['encoding'] != 'base64' ||
                blob['size'] != entry.size ||
                encoded is! String ||
                encoded.length > _fileLimit * 1.5 ||
                !RegExp(r'^[A-Za-z0-9+/=\r\n\t ]*$').hasMatch(encoded)) {
              throw const FormatException('Invalid GitHub blob');
            }
            final bytes = base64.decode(encoded.replaceAll(RegExp(r'\s'), ''));
            final framed = BytesBuilder(copy: false)
              ..add(utf8.encode('blob ${bytes.length}\u0000'))
              ..add(bytes);
            final identity = sha1.convert(framed.takeBytes()).toString();
            if (bytes.length != entry.size || identity != entry.sha) {
              throw const FormatException('GitHub blob integrity mismatch');
            }
            final text = utf8.decode(bytes, allowMalformed: false);
            _cacheBlob(entry.sha, text, bytes.length);
            files[entry.path] = text;
          }),
        );
      }
      _checkCancelled(cancelToken);
      final snapshot = BcrKnowledgeArchive.fromFiles(
        files,
        attachmentSizes: attachmentSizes,
      );
      return BcrGithubRead(target: target, head: head, snapshot: snapshot);
    } on BcrGithubFailure {
      rethrow;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw const BcrGithubFailure(BcrGithubFailureCode.network);
    } catch (_) {
      throw const BcrGithubFailure(BcrGithubFailureCode.invalidData);
    }
  }

  String? _cachedBlob(String sha, int size) {
    final cached = _blobs[sha];
    if (cached == null) return null;
    if (cached.bytes != size) {
      throw const FormatException('Cached Git blob size mismatch');
    }
    _blobs.remove(sha);
    _blobs[sha] = cached;
    return cached.text;
  }

  void _cacheBlob(String sha, String text, int bytes) {
    final previous = _blobs.remove(sha);
    if (previous != null) _blobBytes -= previous.bytes;
    while (_blobs.isNotEmpty &&
        (_blobBytes + bytes > _blobBudget || _blobs.length >= 11010)) {
      _blobBytes -= _blobs.remove(_blobs.keys.first)!.bytes;
    }
    _blobs[sha] = (text: text, bytes: bytes);
    _blobBytes += bytes;
  }

  Future<Map<String, Object?>> _request(
    String url,
    String token,
    CancelToken? external,
  ) async {
    _checkCancelled(external);
    final cancel = CancelToken();
    var finished = false;
    if (external != null) {
      unawaited(
        external.whenCancel.then((_) {
          if (!finished && !cancel.isCancelled) cancel.cancel('cancelled');
        }),
      );
    }
    try {
      return await _readJson(url, token, cancel).timeout(
        _timeout,
        onTimeout: () {
          if (!cancel.isCancelled) cancel.cancel('timeout');
          throw const BcrGithubFailure(BcrGithubFailureCode.network);
        },
      );
    } on BcrGithubFailure {
      if (!cancel.isCancelled) cancel.cancel('failed');
      rethrow;
    } on DioException {
      _checkCancelled(external);
      throw const BcrGithubFailure(BcrGithubFailureCode.network);
    } on FormatException {
      if (!cancel.isCancelled) cancel.cancel('invalid response');
      throw const BcrGithubFailure(BcrGithubFailureCode.invalidData);
    } catch (_) {
      _checkCancelled(external);
      if (!cancel.isCancelled) cancel.cancel('failed');
      throw const BcrGithubFailure(BcrGithubFailureCode.network);
    } finally {
      finished = true;
    }
  }

  Future<Map<String, Object?>> _readJson(
    String url,
    String token,
    CancelToken cancel,
  ) async {
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(
        method: 'GET',
        responseType: ResponseType.stream,
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (_) => true,
        headers: <String, String>{
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2026-03-10',
        },
      ),
    );
    final status = response.statusCode ?? 0;
    if (response.isRedirect ||
        response.redirects.isNotEmpty ||
        status < 200 ||
        status >= 300) {
      throw _httpFailure(status, response.headers);
    }
    final body = response.data;
    if (body == null) throw const FormatException('Missing GitHub body');
    final declared = response.headers.value('content-length');
    if (declared != null &&
        (int.tryParse(declared) == null || int.parse(declared) > _jsonLimit)) {
      throw const FormatException('Oversized GitHub response');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > _jsonLimit) {
        throw const FormatException('Oversized GitHub response');
      }
      bytes.add(chunk);
    }
    return _object(
      jsonDecode(utf8.decode(bytes.takeBytes(), allowMalformed: false)),
    );
  }
}

/// Dio eagerly subscribes to ResponseType.stream before returning its response.
/// Bound the adapter's source first, so that intermediate stream buffering also
/// remains inside the JSON budget rather than merely bounding our final buffer.
class _BoundedGithubAdapter implements HttpClientAdapter {
  _BoundedGithubAdapter(this._delegate);
  final HttpClientAdapter _delegate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await _delegate.fetch(
      options,
      requestStream,
      cancelFuture,
    );
    response.stream = _bounded(response.stream);
    return response;
  }

  Stream<Uint8List> _bounded(Stream<Uint8List> source) async* {
    var bytes = 0;
    await for (final chunk in source) {
      bytes += chunk.length;
      if (bytes > BcrGithubClient._jsonLimit) {
        throw const FormatException('Oversized GitHub response');
      }
      yield chunk;
    }
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid GitHub object');
  }
  return value.cast<String, Object?>();
}

String _sha(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{40}$').hasMatch(value)) {
    throw const FormatException('Invalid Git object identity');
  }
  return value;
}

void _checkIdentity(Object? value, String expected) {
  if (value != null && _sha(value) != expected) {
    throw const FormatException('Git object identity mismatch');
  }
}

void _checkCancelled(CancelToken? token) {
  if (token?.isCancelled ?? false) {
    throw DioException.requestCancelled(
      requestOptions: RequestOptions(),
      reason: 'cancelled',
    );
  }
}

BcrGithubFailure _httpFailure(int status, Headers headers) {
  final limited =
      status == 429 ||
      (status == 403 &&
          (headers.value('x-ratelimit-remaining') == '0' ||
              headers.value('retry-after') != null));
  final code = switch (status) {
    401 => BcrGithubFailureCode.unauthorized,
    403 when !limited => BcrGithubFailureCode.forbidden,
    404 || 409 => BcrGithubFailureCode.notFound,
    _ when limited => BcrGithubFailureCode.rateLimited,
    408 => BcrGithubFailureCode.network,
    >= 500 => BcrGithubFailureCode.network,
    _ => BcrGithubFailureCode.invalidData,
  };
  final now = DateTime.now().toUtc();
  final value = headers.value('retry-after');
  final seconds = value == null ? null : int.tryParse(value);
  final httpDate = value == null ? null : _httpDate(value);
  final resetSeconds = int.tryParse(headers.value('x-ratelimit-reset') ?? '');
  final reset =
      resetSeconds != null && resetSeconds >= 0 && resetSeconds < 8640000000000
      ? DateTime.fromMillisecondsSinceEpoch(resetSeconds * 1000, isUtc: true)
      : null;
  final delay = seconds != null && seconds > 0 && seconds <= 31536000
      ? Duration(seconds: seconds)
      : httpDate?.difference(now) ?? (limited ? reset?.difference(now) : null);
  return BcrGithubFailure(
    code,
    retryAfter: delay != null && delay > Duration.zero
        ? delay
        : limited
        ? const Duration(minutes: 1)
        : null,
  );
}

DateTime? _httpDate(String value) {
  final match = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (match == null) return null;
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months.indexOf(match.group(2)!) + 1;
  if (month == 0) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}
