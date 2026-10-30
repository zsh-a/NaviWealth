import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/meal_photo_saver.dart';
import 'package:naviwealth/features/health/domain/meal_photo.dart';
import 'package:naviwealth/features/health/ui/meal_photo_list.dart';
import 'package:naviwealth/features/health/ui/meal_photo_preview.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../support/test_app_theme.dart';

class _Saver extends MealPhotoSaver {
  final savedBytes = <Uint8List>[];
  Completer<void>? gate;
  Object? error;
  bool available = true;

  @override
  bool get supported => available;

  @override
  Future<void> save(Uint8List bytes) async {
    savedBytes.add(bytes);
    await gate?.future;
    if (error case final error?) throw error;
  }
}

final _photos = [
  MealPhoto(
    bytes: Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8))),
  ),
  MealPhoto(
    bytes: Uint8List.fromList(img.encodeJpg(img.Image(width: 12, height: 8))),
    role: MealPhotoRole.side,
    timestampMs: 500,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  _Saver saver, {
  Locale locale = const Locale('en'),
  double width = 400,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mealPhotoSaverProvider.overrideWithValue(saver)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: buildTestAppTheme(context, child),
        ),
        home: Scaffold(
          body: MealPhotoList(
            photos: _photos,
            onRoleChanged: null,
            onRemove: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('meal-view-preview-1')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'preview exports only the selected frame and prevents duplicate saves',
    (tester) async {
      final saver = _Saver()..gate = Completer<void>();
      await _pump(tester, saver);
      expect(saver.savedBytes, isEmpty);
      final saveButton = find.byKey(const Key('meal-photo-save'));
      await tester.tap(saveButton);
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(saveButton);
      await tester.pump();
      expect(saver.savedBytes, [_photos[1].bytes]);

      saver.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Saved to photos.'), findsOneWidget);
      expect(saveButton, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (error, message) in <(Object, String)>[
    (
      const MealPhotoSaveException(MealPhotoSaveFailure.permissionDenied),
      'Allow photo or storage access for NaviWealth in system settings, then try again.',
    ),
    (
      const MealPhotoSaveException(MealPhotoSaveFailure.insufficientSpace),
      'Your device is out of storage. Free up space and try again.',
    ),
    (
      StateError('private platform details'),
      'Could not save this photo. Please try again.',
    ),
  ]) {
    testWidgets('save failure offers retry: $message', (tester) async {
      final saver = _Saver()..error = error;
      await _pump(tester, saver);
      final saveButton = find.byKey(const Key('meal-photo-save'));
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('private platform'), findsNothing);
      expect(find.byType(MealPhotoPreview), findsOneWidget);
      saver.error = null;
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(find.text('Saved to photos.'), findsOneWidget);
      expect(find.text(message), findsNothing);
      expect(saver.savedBytes, hasLength(2));
    });
  }

  testWidgets('closing a preview during a save is safe', (tester) async {
    final saver = _Saver()..gate = Completer<void>();
    await _pump(tester, saver);
    await tester.tap(find.byKey(const Key('meal-photo-save')));
    await tester.pump();
    Navigator.of(tester.element(find.byType(MealPhotoPreview))).pop();
    await tester.pumpAndSettle();
    saver.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(saver.savedBytes, [_photos[1].bytes]);
  });

  testWidgets('Chinese preview fits a narrow screen with large text', (
    tester,
  ) async {
    final saver = _Saver();
    await _pump(
      tester,
      saver,
      locale: const Locale('zh'),
      width: 320,
      scale: 1.8,
    );
    await tester.ensureVisible(find.byKey(const Key('meal-photo-save')));
    await tester.tap(find.text('保存到相册'));
    await tester.pumpAndSettle();
    expect(find.text('已保存到相册。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported platforms retain the image preview', (tester) async {
    final saver = _Saver()..available = false;
    await _pump(tester, saver);
    expect(find.byType(MealPhotoPreview), findsOneWidget);
    expect(find.byKey(const Key('meal-photo-save')), findsNothing);
    expect(saver.savedBytes, isEmpty);
  });
}
