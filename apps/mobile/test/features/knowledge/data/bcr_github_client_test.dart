import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/bcr_github_client.dart';

void main() {
  test('reads the default branch using only fixed-origin GETs and Git blob integrity', () async {
    final server = _GitHub();
    final result = await _client(server)
        .read(repository: 'Alice/Notes', token: 'fixture-token');
    expect(result.target.owner, 'alice');
    expect(result.target.repository, 'notes');
    expect(result.target.branch, 'trunk');
    expect(result.head, server.head);
    expect(result.snapshot!.notes.single.id, 'source-note-1');
    expect(
      server.calls.every(
        (options) =>
            options.method == 'GET' && options.uri.host == 'api.github.com',
      ),
      isTrue,
    );
    expect(
      server.calls.every(
        (options) => !options.followRedirects && options.maxRedirects == 0,
      ),
      isTrue,
    );
    expect(server.calls.first.headers['Authorization'], 'Bearer fixture-token');
    expect(server.calls.first.headers['X-GitHub-Api-Version'], '2026-03-10');
    expect(
      server.calls.any(
        (options) => options.uri.path.endsWith('/git/ref/heads/trunk'),
      ),
      isTrue,
    );
    expect(
      server.blobReads,
      server.files.keys.where((path) => path.startsWith('knowledge/')).length,
    );
  });

  test('encodes explicit nested branch names and skips immutable cached content on same HEAD', () async {
    final server = _GitHub();
    final result = await _client(server).read(
      repository: 'alice/notes',
      token: 'token',
      branch: 'Notes/sync',
      knownHead: server.head,
      hasCachedSnapshot: true,
    );
    expect(result.target.branch, 'Notes/sync');
    expect(result.snapshot, isNull);
    expect(server.calls.length, 2);
    expect(server.calls.last.uri.toString(), contains('Notes%2Fsync'));
  });

  test('does a full read when cached HEAD lacks a usable snapshot', () async {
    final server = _GitHub();
    final client = _client(server);
    final result = await client.read(
      repository: 'alice/notes',
      token: 'token',
      knownHead: server.head,
    );
    expect(result.snapshot, isNotNull);
    expect(server.blobReads, greaterThan(0));
    final downloaded = server.blobReads;
    server.head = 'c' * 40;
    final refreshed = await client.read(
      repository: 'alice/notes',
      token: 'token',
    );
    expect(refreshed.head, server.head);
    expect(
      refreshed.snapshot!.notes.single.fingerprint,
      result.snapshot!.notes.single.fingerprint,
    );
    expect(server.blobReads, downloaded);
  });

  test(
    'retries quota failures using only already verified immutable blobs',
    () async {
      final server = _GitHub();
      server.failedBlobSha = _blobId(
        server.files['knowledge/notes/source-note-1.md']!,
      );
      final client = _client(server);
      await expectLater(
        client.read(repository: 'alice/notes', token: 'token'),
        _failure(BcrGithubFailureCode.rateLimited),
      );
      final downloaded = server.blobReads;
      server.failedBlobSha = null;
      final completed = await client.read(
        repository: 'alice/notes',
        token: 'token',
      );
      expect(completed.snapshot!.notes.single.id, 'source-note-1');
      expect(server.blobReads - downloaded, 1);
    },
  );

  test('evicts older blobs when verified UTF-8 content exceeds the 16 MiB budget', () async {
    final server = _GitHub();
    final body = '中' * 499999;
    Map<String, Uint8List> largeFiles(
      String prefix,
      int count,
    ) => <String, Uint8List>{
      for (var index = 0; index < count; index++)
        'knowledge/notes/large-$prefix-$index.md': Uint8List.fromList(
          utf8.encode(
            '---\nbcr: 1\nid: large-$prefix-$index\ntitle: Large\ntags: []\ncollectionId: null\ncreatedAt: 1\nupdatedAt: 2\n---\n$body',
          ),
        ),
      for (var index = 0; index < count; index++)
        'knowledge/citations/large-$prefix-$index.json': Uint8List.fromList(
          utf8.encode('[]'),
        ),
    };
    final base = Map<String, Uint8List>.of(server.files);
    server.files.addAll(largeFiles('old', 9));
    final first = Map<String, Uint8List>.of(server.files);
    final oldest = _blobId(first['knowledge/notes/large-old-0.md']!);
    final newest = _blobId(first['knowledge/notes/large-old-8.md']!);
    final client = _client(server);
    await client.read(repository: 'alice/notes', token: 'token');
    server.files
      ..clear()
      ..addAll(base)
      ..addAll(largeFiles('new', 3));
    server.head = 'c' * 40;
    await client.read(repository: 'alice/notes', token: 'token');
    server.files
      ..clear()
      ..addAll(first);
    server.head = 'd' * 40;
    await client.read(repository: 'alice/notes', token: 'token');
    int reads(String sha) => server.calls
        .where((call) => call.uri.path.endsWith('/git/blobs/$sha'))
        .length;
    expect(reads(oldest), 2);
    expect(reads(newest), 1);
  });

  test('rechecks privacy before the same-HEAD fast path', () async {
    final server = _GitHub()..private = false;
    await expectLater(
      _client(server).read(
        repository: 'alice/notes',
        token: 'token',
        knownHead: server.head,
        hasCachedSnapshot: true,
      ),
      _failure(BcrGithubFailureCode.forbidden),
    );
    expect(server.calls.length, 1);
  });

  test(
    'rejects invalid repository, branch and empty token before HTTP',
    () async {
      final server = _GitHub();
      final client = _client(server);
      await expectLater(
        client.read(repository: 'https://evil.test/a/b', token: 'token'),
        _failure(BcrGithubFailureCode.invalidRepository),
      );
      await expectLater(
        client.read(
          repository: 'alice/notes',
          token: 'token',
          branch: '../main',
        ),
        _failure(BcrGithubFailureCode.invalidRepository),
      );
      await expectLater(
        client.read(repository: 'alice/notes', token: ' '),
        _failure(BcrGithubFailureCode.unauthorized),
      );
      expect(server.calls, isEmpty);
    },
  );

  test(
    'never inherits app auth, logging interceptors or query parameters',
    () async {
      final server = _GitHub();
      var intercepted = false;
      final appDio =
          Dio(
              BaseOptions(
                headers: {'Authorization': 'NAVI-SECRET'},
                queryParameters: {'token': 'NAVI-SECRET'},
              ),
            )
            ..httpClientAdapter = server
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  intercepted = true;
                  handler.next(options);
                },
              ),
            );
      await BcrGithubClient(appDio)
          .read(repository: 'alice/notes', token: 'github-token');
      expect(intercepted, isFalse);
      expect(
        server.calls.every(
          (options) => !options.uri.toString().contains('SECRET'),
        ),
        isTrue,
      );
      expect(
        server.calls.every(
          (options) =>
              options.headers['Authorization'] == 'Bearer github-token',
        ),
        isTrue,
      );
    },
  );

  test('maps HTTP failures without retaining private response bodies or credentials', () async {
    const cases = <int, BcrGithubFailureCode>{
      401: BcrGithubFailureCode.unauthorized,
      403: BcrGithubFailureCode.forbidden,
      404: BcrGithubFailureCode.notFound,
      429: BcrGithubFailureCode.rateLimited,
      408: BcrGithubFailureCode.network,
      503: BcrGithubFailureCode.network,
      302: BcrGithubFailureCode.invalidData,
    };
    for (final entry in cases.entries) {
      final server = _GitHub()
        ..reply = (options) => ResponseBody.fromString(
          'fixture-secret-response',
          entry.key,
          headers: {
            'location': ['https://evil.test/'],
          },
        );
      try {
        await _client(server)
            .read(repository: 'alice/notes', token: 'fixture-secret-token');
        fail('Expected failure');
      } on BcrGithubFailure catch (error) {
        expect(error.code, entry.value);
        expect(error.toString(), isNot(contains('secret')));
      }
      expect(server.calls.length, 1);
    }
  });

  test(
    'honors Retry-After and rate-limit reset without retrying ordinary 403',
    () async {
      final server = _GitHub()
        ..reply = (_) => ResponseBody.fromString(
          '',
          403,
          headers: {
            'retry-after': ['120'],
          },
        );
      await expectLater(
        _client(server).read(repository: 'alice/notes', token: 'token'),
        throwsA(
          isA<BcrGithubFailure>()
              .having(
                (error) => error.code,
                'code',
                BcrGithubFailureCode.rateLimited,
              )
              .having(
                (error) => error.retryAfter,
                'retry',
                const Duration(seconds: 120),
              ),
        ),
      );
      server.reply = (_) => ResponseBody.fromString(
        '',
        403,
        headers: {
          'x-ratelimit-remaining': ['0'],
          'x-ratelimit-reset': [
            '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 180}',
          ],
        },
      );
      await expectLater(
        _client(server).read(repository: 'alice/notes', token: 'token'),
        throwsA(
          isA<BcrGithubFailure>().having(
            (error) => error.retryAfter!.inSeconds,
            'retry',
            inInclusiveRange(178, 180),
          ),
        ),
      );
    },
  );

  test(
    'rejects incomplete trees, symlinks, malformed SHAs and duplicate paths',
    () async {
      for (final configure in <void Function(_GitHub)>[
        (server) => server.truncated = true,
        (server) => server.mode = '120000',
        (server) => server.extraTree = {
          'path': 'knowledge/notes/other.md',
          'sha': 'bad',
          'mode': '100644',
          'type': 'blob',
          'size': 1,
        },
        (server) => server.extraTree = server.treeEntries.first,
      ]) {
        final server = _GitHub();
        configure(server);
        await expectLater(
          _client(server).read(repository: 'alice/notes', token: 'token'),
          _failure(BcrGithubFailureCode.invalidData),
        );
        expect(server.blobReads, 0);
      }
    },
  );

  test(
    'rejects blob length, encoding, returned SHA and actual Git SHA mismatches',
    () async {
      for (final mutation in <Map<String, Object?>>[
        {'encoding': 'utf-8'},
        {'size': -1},
        {'sha': 'f' * 40},
        {'content': base64Encode(utf8.encode('corrupted'))},
      ]) {
        final server = _GitHub()..blobPatch = mutation;
        final client = _client(server);
        await expectLater(
          client.read(repository: 'alice/notes', token: 'token'),
          _failure(BcrGithubFailureCode.invalidData),
        );
        final downloaded = server.blobReads;
        server.blobPatch = {};
        await client.read(repository: 'alice/notes', token: 'token');
        expect(server.blobReads - downloaded, 3);
      }
      final invalidUtf8 = _GitHub()
        ..files['knowledge/notes/other.md'] = Uint8List.fromList([0xff]);
      await expectLater(
        _client(invalidUtf8).read(repository: 'alice/notes', token: 'token'),
        _failure(BcrGithubFailureCode.invalidData),
      );
    },
  );

  test(
    'bounds JSON response bytes before decoding or accumulating later chunks',
    () async {
      final server = _GitHub();
      var chunksRead = 0;
      Stream<Uint8List> oversized() async* {
        for (var index = 0; index < 5; index++) {
          chunksRead++;
          yield Uint8List(4 * 1024 * 1024);
        }
      }

      server.reply = (_) => ResponseBody(oversized(), 200);
      await expectLater(
        _client(server).read(repository: 'alice/notes', token: 'token'),
        _failure(BcrGithubFailureCode.invalidData),
      );
      expect(chunksRead, lessThanOrEqualTo(4));
    },
  );

  test('bounds declared text size before downloading blobs', () async {
    final server = _GitHub()
      ..extraTree = {
        'path': 'knowledge/notes/large.md',
        'sha': 'c' * 40,
        'mode': '100644',
        'type': 'blob',
        'size': 2 * 1024 * 1024 + 1,
      };
    await expectLater(
      _client(server).read(repository: 'alice/notes', token: 'token'),
      _failure(BcrGithubFailureCode.invalidData),
    );
    expect(server.blobReads, 0);
  });

  test('validates attachment metadata against the tree without reading binary blobs', () async {
    final server = _GitHub(fixture: 'bcr-v4.zip');
    final result = await _client(server)
        .read(repository: 'alice/notes', token: 'token');
    expect(result.snapshot!.attachmentCount, 1);
    final binary = server.files.entries.singleWhere(
      (entry) => entry.key.endsWith('.bin'),
    );
    final blobPath = '/git/blobs/${_blobId(binary.value)}';
    expect(
      server.calls.any((options) => options.uri.path.endsWith(blobPath)),
      isFalse,
    );
    server.files.remove(binary.key);
    await expectLater(
      _client(server).read(repository: 'alice/notes', token: 'token'),
      _failure(BcrGithubFailureCode.invalidData),
    );
  });

  test(
    'sanitizes network errors and preserves explicit cancellation',
    () async {
      final server = _GitHub()..networkError = true;
      await expectLater(
        _client(server)
            .read(repository: 'alice/notes', token: 'fixture-secret-token'),
        _failure(BcrGithubFailureCode.network),
      );
      final cancel = CancelToken()..cancel('fixture-secret-reason');
      await expectLater(
        _client(server).read(
          repository: 'alice/notes',
          token: 'fixture-secret-token',
          cancelToken: cancel,
        ),
        throwsA(
          isA<DioException>()
              .having((error) => error.type, 'type', DioExceptionType.cancel)
              .having(
                (error) => error.toString(),
                'redacted',
                isNot(contains('fixture-secret')),
              ),
        ),
      );
    },
  );
}

Matcher _failure(BcrGithubFailureCode code) => throwsA(
  isA<BcrGithubFailure>().having((error) => error.code, 'code', code),
);

BcrGithubClient _client(_GitHub server) =>
    BcrGithubClient(Dio()..httpClientAdapter = server);

String _blobId(Uint8List bytes) => sha1.convert(<int>[
  ...utf8.encode('blob ${bytes.length}\u0000'),
  ...bytes,
]).toString();

class _GitHub implements HttpClientAdapter {
  _GitHub({String fixture = 'bcr-v2.zip'}) {
    for (final file in ZipDecoder().decodeBytes(
      File('test/fixtures/knowledge/bcr/$fixture').readAsBytesSync(),
    )) {
      files[file.name] = file.readBytes()!;
    }
    files['README.md'] = Uint8List.fromList(
      utf8.encode('unrelated repository file'),
    );
  }

  final files = <String, Uint8List>{};
  final calls = <RequestOptions>[];
  String head = 'a' * 40;
  final String tree = 'b' * 40;
  bool private = true;
  bool truncated = false;
  bool networkError = false;
  String mode = '100644';
  Map<String, Object?>? extraTree;
  Map<String, Object?> blobPatch = {};
  String? failedBlobSha;
  ResponseBody Function(RequestOptions)? reply;
  int blobReads = 0;

  List<Map<String, Object?>> get treeEntries => <Map<String, Object?>>[
    for (final entry in files.entries)
      <String, Object?>{
        'path': entry.key,
        'type': 'blob',
        'mode': entry.key.startsWith('knowledge/') ? mode : '100644',
        'size': entry.value.length,
        'sha': _blobId(entry.value),
      },
    ?extraTree,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    if (networkError) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'fixture-secret-network-error',
      );
    }
    if (reply != null) return reply!(options);
    final path = Uri.decodeComponent(
      options.uri.path.replaceFirst('/repos/alice/notes', ''),
    );
    Object body;
    if (path.isEmpty) {
      body = {'private': private, 'default_branch': 'trunk'};
    } else if (path.startsWith('/git/ref/heads/')) {
      body = {
        'object': {'sha': head, 'type': 'commit'},
      };
    } else if (path == '/git/commits/$head') {
      body = {
        'sha': head,
        'tree': {'sha': tree},
      };
    } else if (path == '/git/trees/$tree') {
      body = {'sha': tree, 'truncated': truncated, 'tree': treeEntries};
    } else if (path.startsWith('/git/blobs/')) {
      blobReads++;
      final id = path.split('/').last;
      if (id == failedBlobSha) {
        return ResponseBody.fromString(
          '',
          429,
          headers: {
            'retry-after': ['120'],
          },
        );
      }
      final bytes = files.values.firstWhere((bytes) => _blobId(bytes) == id);
      body = <String, Object?>{
        'sha': id,
        'encoding': 'base64',
        'size': bytes.length,
        'content': base64Encode(bytes),
        ...blobPatch,
      };
    } else {
      throw StateError('Unexpected fixture request');
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
