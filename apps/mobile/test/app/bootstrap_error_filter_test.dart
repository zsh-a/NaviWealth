import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/bootstrap.dart';

void main() {
  test('classifies Flutter duplicate KeyDown assertion as benign', () {
    final details = FlutterErrorDetails(
      exception: AssertionError(
        "'package:flutter/src/services/hardware_keyboard.dart': "
        'Failed assertion: line 516 pos 11: '
        "'!_pressedKeys.containsKey(event.physicalKey)': "
        'A KeyDownEvent is dispatched, but the state shows that the physical '
        'key is already pressed.',
      ),
    );

    expect(isBenignDuplicateKeyDownAssertion(details), isTrue);
  });

  test('does not classify unrelated framework errors as benign', () {
    final details = FlutterErrorDetails(
      exception: AssertionError(
        'setState() or markNeedsBuild() called during build.',
      ),
    );

    expect(isBenignDuplicateKeyDownAssertion(details), isFalse);
  });
}
