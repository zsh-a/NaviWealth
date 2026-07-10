import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef FormClock = DateTime Function();

final formClockProvider = Provider<FormClock>((_) => DateTime.now);
