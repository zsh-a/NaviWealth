import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/shared/forms/form_dirty_guard.dart';

void main() {
  group('FormDirtyController', () {
    test('starts pristine', () {
      final c = FormDirtyController();
      addTearDown(c.dispose);
      expect(c.isDirty, isFalse);
      expect(c.busy, isFalse);
    });

    test('a user edit that diverges from the baseline flips dirty', () {
      final c = FormDirtyController();
      final field = TextEditingController();
      addTearDown(c.dispose);
      addTearDown(field.dispose);

      c.bindTextControllers([field]);
      expect(c.isDirty, isFalse);

      field.text = 'typed';
      expect(c.isDirty, isTrue);
    });

    test('an async hydrate is not a user edit when re-baselined', () {
      final c = FormDirtyController();
      final field = TextEditingController();
      addTearDown(c.dispose);
      addTearDown(field.dispose);

      c.bindTextControllers([field]);
      // Simulate _loadInitial populating the controller, then snapshot.
      field.text = 'loaded value';
      c.snapshotBaseline();
      // markDirty/_onBoundChanged compares against the new baseline; a
      // listener fire after snapshot with unchanged text stays pristine.
      c.markPristine();
      expect(c.isDirty, isFalse);

      field.text = 'loaded value 2';
      expect(c.isDirty, isTrue);
    });

    test('markPristine clears dirty and notifies once', () {
      final c = FormDirtyController();
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.markDirty();
      expect(c.isDirty, isTrue);
      expect(notifications, 1);

      c.markPristine();
      expect(c.isDirty, isFalse);
      expect(notifications, 2);

      // No-op when already pristine.
      c.markPristine();
      expect(notifications, 2);
    });

    test('busy is independent of dirty and notifies', () {
      final c = FormDirtyController();
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.busy = true;
      expect(c.busy, isTrue);
      expect(c.isDirty, isFalse);
      expect(notifications, 1);

      // Idempotent.
      c.busy = true;
      expect(notifications, 1);

      c.busy = false;
      expect(notifications, 2);
    });
  });
}
