// Only meaningful under `flutter test --platform chrome --wasm`: dart2js
// selects the no-op web isolate handler regardless, so it passes either way.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/error_tracking/txlemetry_error_tracking_autocapture_integration.dart';
import 'package:txlemetry_flutter/src/txlemetry_config.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

void main() {
  tearDown(TxlemetryErrorTrackingAutoCaptureIntegration.uninstall);

  test('install with captureIsolateErrors does not throw on web', () {
    final config = TxlemetryErrorTrackingConfig()..captureIsolateErrors = true;

    final integration = TxlemetryErrorTrackingAutoCaptureIntegration.install(
      config: config,
      txlemetry: TxlemetryFlutterPlatformFake(),
    );

    expect(integration, isNotNull);
  });
}
