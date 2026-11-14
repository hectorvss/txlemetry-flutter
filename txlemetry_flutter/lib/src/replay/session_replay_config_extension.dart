import 'package:txlemetry_flutter/src/txlemetry_config.dart';

extension SessionReplayMasking on TxlemetrySessionReplayConfig {
  bool get masksAnyContent =>
      maskAllTexts ||
      maskAllImages ||
      maskCustomPaint ||
      textMaskPolicy != null;
}
