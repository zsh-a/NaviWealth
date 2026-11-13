import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart'
    show resolveLlmProfileModel;
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_profile_completion_clients.dart';
import 'package:naviwealth/app/agent_runtime/bridges/health_meal_native_bridge.dart';
import 'package:naviwealth/core/ai/contracts/ai_domain.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/features/health/data/meal_photo_capture.dart';
import 'package:naviwealth/features/health/data/meal_recognition_client.dart';
import 'package:naviwealth/features/health/domain/meal_photo.dart';

class _NativeBridge implements HealthMealNativeBridge {
  _NativeBridge(this.complete);
  final Future<Map<String, Object?>> Function(Map<String, Object?>) complete;
  @override
  Future<Map<String, Object?>> recognize({
    required Map<String, Object?> request,
  }) => complete(request);
  @override
  Future<Uint8List> normalizePhoto(Uint8List bytes) async => bytes;
}

class _NativeApi implements HealthMealNativeApi {
  String? requestJson;
  Uint8List? photoBytes;

  @override
  Future<String> recognize({required String requestJson}) async {
    this.requestJson = requestJson;
    return jsonEncode(_result());
  }

  @override
  Future<Uint8List> normalizePhoto({required Uint8List bytes}) async {
    photoBytes = bytes;
    return Uint8List.fromList([10, 20, 30]);
  }
}

Map<String, Object?> _result() => {
  'model': 'test-vision',
  'provider': 'openai',
  'finish_reason': 'stop',
  'usage': {'input_tokens': 10, 'output_tokens': 20, 'total_tokens': 30},
  'prompt_version': 'meal-v1',
  'title': '米饭',
  'foods': [
    {
      'name': '米饭（熟）',
      'grams': 200,
      'catalog_id': '168878',
      'source': 'USDA FDC 168878',
      'per_100g': {'kcal': 130, 'protein': 2.69, 'carbs': 28.17, 'fat': 0.28},
    },
  ],
};

void main() {
  test('normalization requires native composition while manual meals remain independent', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () =>
          container.read(mealPhotoNormalizerProvider)(Uint8List.fromList([1])),
      throwsUnsupportedError,
    );
    expect(container.read(mealRecognitionClientProvider), isNull);
  });

  test('profile defaults and explicit overrides resolve before consent', () {
    const profile = LlmProfile(
      id: 'profile',
      name: 'Vision',
      provider: LlmProvider.anthropic,
      apiKey: 'key',
    );
    expect(resolveLlmProfileModel(profile), kDefaultDeviceModel);
    expect(
      resolveLlmProfileModel(profile.copyWith(model: '  custom-vision  ')),
      'custom-vision',
    );
    expect(
      resolveLlmProfileModel(profile.copyWith(provider: LlmProvider.openai)),
      'gpt-5-mini',
    );
  });

  test('shared-core DTO maps into editable Host foods with provenance', () {
    final draft = mealRecognitionDraftFromCore(_result());
    expect(draft.foods.single.nutrients.kcal, 260);
    expect(draft.foods.single.source, 'USDA FDC 168878');
    expect(draft.foods.single.catalogId, '168878');
    expect(draft.model, 'test-vision');
    expect(draft.promptVersion, 'meal-v1');
    expect(draft.title, '米饭');
  });

  test(
    'Host accepts only the validated core contract, never provider text',
    () {
      for (final response in [
        {'content': jsonEncode(_result())},
        {'object': _result()},
        {..._result(), 'prompt_version': null},
        {..._result(), 'foods': <Object?>[]},
        {
          ..._result(),
          'foods': <Object?>[null],
        },
      ]) {
        expect(
          () => mealRecognitionDraftFromCore(response),
          throwsFormatException,
        );
      }
    },
  );

  test('consent denial prevents native calls; frozen profile and all views cross the core boundary', () async {
    final calls = <Map<String, Object?>>[];
    final traces = <Map<String, Object?>>[];
    final native = _NativeBridge((request) async {
      calls.add(request);
      return _result();
    });
    final client = FrbMealRecognitionClient(
      nativeBridge: native,
      profile: const LlmProfile(
        id: 'profile',
        name: 'Vision',
        provider: LlmProvider.openai,
        apiKey: 'test-key',
        baseUrl: 'https://vision.example/v1',
        model: 'test-vision',
      ),
      recordTrace:
          ({
            required String agentId,
            required Map<String, Object?>? llmResponse,
            DateTime? startedAt,
            DateTime? finishedAt,
            String? requestId,
            required AiDomain domain,
            String surface = '',
            String routingReason = '',
            Object? error,
          }) async {
            traces.add({
              'agent': agentId,
              'domain': domain.wire,
              'surface': surface,
              'response': llmResponse,
              'error': error,
            });
            return null;
          },
    );
    expect(
      client.providerLabel,
      'Vision · test-vision\nhttps://vision.example/v1',
    );
    final photos = [
      MealPhoto(bytes: Uint8List.fromList([1])),
      MealPhoto(
        bytes: Uint8List.fromList([2]),
        role: MealPhotoRole.side,
        timestampMs: 1200,
      ),
      MealPhoto(bytes: Uint8List.fromList([3]), role: MealPhotoRole.afterMeal),
      MealPhoto(bytes: Uint8List.fromList([4]), role: MealPhotoRole.label),
    ];
    await expectLater(
      client.recognize(photos: photos, languageCode: 'zh', allowUpload: false),
      throwsStateError,
    );
    expect(calls, isEmpty);
    expect(traces, isEmpty);
    final draft = await client.recognize(
      photos: photos,
      languageCode: 'zh',
      allowUpload: true,
      context: '两人分食，熟米饭 150g',
    );
    expect(draft.foods.single.nutrients.kcal, 260);
    expect(calls.single, {
      'provider': 'openai',
      'model': 'test-vision',
      'base_url': 'https://vision.example/v1',
      'api_key': 'test-key',
      'allow_upload': true,
      'language_code': 'zh',
      'context': '两人分食，熟米饭 150g',
      'photos': [
        {
          'bytes': [1],
          'role': 'overview',
        },
        {
          'bytes': [2],
          'role': 'side',
          'timestamp_ms': 1200,
        },
        {
          'bytes': [3],
          'role': 'after_meal',
        },
        {
          'bytes': [4],
          'role': 'label',
        },
      ],
    });
    expect(traces.single['domain'], 'health');
    expect(traces.single['response'], {
      'model': 'test-vision',
      'provider': 'openai',
      'finish_reason': 'stop',
      'usage': {'input_tokens': 10, 'output_tokens': 20, 'total_tokens': 30},
      'metadata': {'prompt_version': 'meal-v1'},
    });
    expect(jsonEncode(traces), isNot(contains('test-key')));
    expect(jsonEncode(traces), isNot(contains('两人分食')));
    expect(jsonEncode(traces), isNot(contains('foods')));
  });

  test(
    'native normalization and recognition share initialized local runtime',
    () async {
      final api = _NativeApi();
      final paths = <String?>[];
      final bridge = FfiHealthMealNativeBridge(
        api: api,
        initialize: ({String? libraryPath}) async => paths.add(libraryPath),
        libraryPath: '/native/lifeos',
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(await bridge.normalizePhoto(bytes), [10, 20, 30]);
      expect(api.photoBytes, same(bytes));
      final result = await bridge.recognize(
        request: {
          'allow_upload': true,
          'photos': [
            {'bytes': bytes},
          ],
        },
      );
      expect(result['prompt_version'], 'meal-v1');
      expect(jsonDecode(api.requestJson!), {
        'allow_upload': true,
        'photos': [
          {
            'bytes': [1, 2, 3],
          },
        ],
      });
      expect(paths, ['/native/lifeos', '/native/lifeos']);
    },
  );

  test('native failures are traced without changing the failure', () async {
    final failure = StateError('recognition_refused');
    Object? tracedError;
    final client = FrbMealRecognitionClient(
      nativeBridge: _NativeBridge((_) async => throw failure),
      profile: const LlmProfile(
        id: 'p',
        name: 'Vision',
        provider: LlmProvider.anthropic,
        apiKey: 'key',
        model: 'vision',
      ),
      recordTrace:
          ({
            required String agentId,
            required Map<String, Object?>? llmResponse,
            DateTime? startedAt,
            DateTime? finishedAt,
            String? requestId,
            required AiDomain domain,
            String surface = '',
            String routingReason = '',
            Object? error,
          }) async {
            tracedError = error;
            throw StateError('trace unavailable');
          },
    );
    await expectLater(
      client.recognize(
        photos: [
          MealPhoto(bytes: Uint8List.fromList([1])),
        ],
        languageCode: 'en',
        allowUpload: true,
      ),
      throwsA(same(failure)),
    );
    expect(tracedError, same(failure));
  });
}
