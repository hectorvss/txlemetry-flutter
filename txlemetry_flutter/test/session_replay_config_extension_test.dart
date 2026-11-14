import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/replay/session_replay_config_extension.dart';

void main() {
  for (var flags = 0; flags < 8; flags++) {
    test('masksAnyContent reflects masking flags $flags', () {
      final config = TxlemetrySessionReplayConfig()
        ..maskAllTexts = flags & 1 != 0
        ..maskAllImages = flags & 2 != 0
        ..maskCustomPaint = flags & 4 != 0;
      expect(config.masksAnyContent, flags != 0);
      config
        ..maskAllTexts = false
        ..maskAllImages = false
        ..maskCustomPaint = false;
      expect(config.masksAnyContent, isFalse);
    });
  }
}
