@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/error_tracking/txlemetry_error_tracking_autocapture_integration.dart';
import 'package:txlemetry_flutter/src/txlemetry_config.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('platform error capture is skipped without disabling Flutter errors',
      () {
    final originalHandler = FlutterError.onError;
    final originalPlatformHandler = PlatformDispatcher.instance.onError;
    var forwarded = 0;
    FlutterError.onError = (_) => forwarded++;
    addTearDown(() {
      TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();
      FlutterError.onError = originalHandler;
    });
    final txlemetry = TxlemetryFlutterPlatformFake();
    final config = TxlemetryErrorTrackingConfig()
      ..captureFlutterErrors = true
      ..capturePlatformDispatcherErrors = true;

    for (var i = 0; i < 2; i++) {
      final integration = TxlemetryErrorTrackingAutoCaptureIntegration.install(
        config: config,
        txlemetry: txlemetry,
      );
      expect(integration, isNotNull);
      expect(
          PlatformDispatcher.instance.onError, same(originalPlatformHandler));
      FlutterError.onError!(FlutterErrorDetails(
        exception: StateError('web error'),
        stack: StackTrace.current,
      ));
      TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();
    }

    expect(txlemetry.capturedExceptions, hasLength(2));
    expect(forwarded, 2);
  });
}
