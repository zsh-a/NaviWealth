import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_profile_completion_clients.dart';
import 'package:naviwealth/core/ai/contracts/ai_domain.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/runtime/device/device_system_prompt.dart';
import 'package:naviwealth/features/health/data/meal_photo_capture.dart';
import 'package:naviwealth/features/health/data/meal_recognition_client.dart';
import 'package:naviwealth/features/health/domain/meal_photo.dart';

class _NativeBridge implements AgentRuntimeNativeBridge {
  _NativeBridge(this.complete);
  final Future<Map<String, Object?>> Function(Map<String, Object?>) complete;
  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) => complete(request);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('multiple views carry roles and context for one deduplicated meal', () {
    final messages = mealRecognitionMessages(
      photos: [
        MealPhoto(bytes: Uint8List.fromList([1])),
        MealPhoto(
          bytes: Uint8List.fromList([2]),
          role: MealPhotoRole.side,
          timestampMs: 1200,
        ),
        MealPhoto(
          bytes: Uint8List.fromList([3]),
          role: MealPhotoRole.afterMeal,
        ),
        MealPhoto(bytes: Uint8List.fromList([4]), role: MealPhotoRole.label),
      ],
      languageCode: 'zh',
      context: '两人分食，熟米饭 150g',
    );
    final system = messages.first['content']! as String;
    expect(system, contains('count each serving ONCE'));
    expect(system, contains('leftovers, never additional food'));
    expect(system, contains('1 kcal = 4.184 kJ'));
    final content = messages.last['content']! as List<Map<String, Object?>>;
    expect(content.where((part) => part['type'] == 'image'), hasLength(4));
    expect(content.map((part) => part['text']).join(), contains('after_meal'));
    expect(content.map((part) => part['text']).join(), contains('两人分食'));
    expect(content.map((part) => part['text']).join(), contains('1200'));
  });

  test(
    'recognition rejects excess views, missing meal view and oversized context',
    () {
      for (final photos in [
        <MealPhoto>[],
        List.generate(5, (_) => MealPhoto(bytes: Uint8List.fromList([1]))),
        [
          MealPhoto(
            bytes: Uint8List.fromList([1]),
            role: MealPhotoRole.afterMeal,
          ),
        ],
        [
          MealPhoto(bytes: Uint8List.fromList([1]), role: MealPhotoRole.label),
        ],
      ]) {
        expect(
          () => mealRecognitionMessages(photos: photos, languageCode: 'en'),
          throwsFormatException,
        );
      }
      expect(
        () => mealRecognitionMessages(
          photos: [
            MealPhoto(bytes: Uint8List.fromList([1])),
          ],
          languageCode: 'en',
          context: 'a' * 1001,
        ),
        throwsFormatException,
      );
    },
  );

  Map<String, Object?> response(List<Object?> foods) => {
    'model': 'test-vision',
    'object': {'foods': foods},
  };
  Map<String, Object?> food({String? catalog = '168878', double grams = 200}) =>
      {
        'name': '米饭（熟）',
        'grams': grams,
        'catalog_id': catalog,
        'per_100g': {'kcal': 999, 'protein': 1, 'carbs': 2, 'fat': 3},
      };

  test('catalog-backed nutrition overrides model values; uncataloged recipes stay estimates', () {
    final draft = parseMealRecognition(
      response([food(), food(catalog: null, grams: 100)]),
    );
    expect(draft.foods.first.nutrients.kcal, 260);
    expect(draft.foods.first.source, 'USDA FDC 168878');
    expect(draft.foods.last.nutrients.kcal, 999);
    expect(draft.foods.last.isEstimate, true);
    expect(draft.model, 'test-vision');
  });
  test('empty, unknown, malformed, oversized and truncated results fail without saving guesses', () {
    for (final object in [
      response([]),
      response([food(catalog: 'invented')]),
      response([food(grams: -1)]),
      response([food(grams: double.infinity)]),
      response(List.filled(31, food())),
      {'content': 'not JSON'},
      {
        ...response([food()]),
        'finish_reason': 'length',
      },
    ]) {
      expect(() => parseMealRecognition(object), throwsFormatException);
    }
  });
  test(
    'photo normalization resizes and re-encodes without original metadata',
    () {
      final image = img.Image(width: 1800, height: 900);
      image.exif.imageIfd.imageDescription = 'private original metadata';
      final original = Uint8List.fromList(img.encodeJpg(image));
      final normalized = normalizeMealPhoto(original);
      final decoded = img.decodeJpg(normalized)!;
      expect(decoded.width, 1280);
      expect(decoded.height, 640);
      expect(
        decoded.exif.imageIfd.imageDescription,
        isNot('private original metadata'),
      );
      expect(normalized.length, lessThan(2 * 1024 * 1024));
      expect(
        () => normalizeMealPhoto(Uint8List.fromList([1, 2])),
        throwsFormatException,
      );
    },
  );
  test('permission denial makes no native call and recognition is traced to Health', () async {
    final calls = <Map<String, Object?>>[];
    final traces = <Map<String, Object?>>[];
    final native = _NativeBridge((request) async {
      calls.add(request);
      return response([food()]);
    });
    final client = FrbMealRecognitionClient(
      llmBridge: AgentRuntimeLlmBridge(
        bridge: native,
        profile: const LlmProfile(
          id: 'profile',
          name: 'Vision',
          provider: LlmProvider.openai,
          apiKey: 'test-key',
          model: 'test-vision',
        ),
      ),
      providerLabel: 'Vision',
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
            });
            return null;
          },
    );
    expect(
      () => client.recognize(
        photos: [
          MealPhoto(bytes: Uint8List.fromList([1])),
        ],
        languageCode: 'zh',
        allowUpload: false,
      ),
      throwsStateError,
    );
    expect(calls, isEmpty);
    final draft = await client.recognize(
      photos: List.generate(
        4,
        (index) => MealPhoto(bytes: Uint8List.fromList([index + 1])),
      ),
      languageCode: 'zh',
      allowUpload: true,
    );
    expect(draft.foods.single.nutrients.kcal, 260);
    expect(calls.single['response_format'], {'type': 'json_object'});
    expect(calls.single['max_output_tokens'], kDefaultLlmMaxOutputTokens);
    final messages = calls.single['messages']! as List<Map<String, Object?>>;
    final content = messages.last['content']! as List<Map<String, Object?>>;
    expect(content.where((block) => block['type'] == 'image'), hasLength(4));
    expect(traces.single['domain'], 'health');
  });
}
