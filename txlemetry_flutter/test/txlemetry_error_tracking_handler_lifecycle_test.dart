import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/error_tracking/txlemetry_error_tracking_autocapture_integration.dart';
import 'package:txlemetry_flutter/src/txlemetry_config.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platformHandler in [false, true]) {
    group(
        platformHandler ? 'PlatformDispatcher.onError' : 'FlutterError.onError',
        () {
      late FlutterExceptionHandler? savedFlutterHandler;
      late ErrorCallback? savedPlatformHandler;
      late TxlemetryErrorTrackingConfig config;
      late TxlemetryFlutterPlatformFake txlemetry;
      late TxlemetryErrorTrackingAutoCaptureIntegration integration;
      late bool Function() dispatch;
      var upstreamCalls = 0;
      var wrapperCalls = 0;

      setUp(() {
        savedFlutterHandler = FlutterError.onError;
        savedPlatformHandler = PlatformDispatcher.instance.onError;
        upstreamCalls = 0;
        wrapperCalls = 0;
        txlemetry = TxlemetryFlutterPlatformFake();
        config = TxlemetryErrorTrackingConfig()
          ..captureFlutterErrors = !platformHandler
          ..capturePlatformDispatcherErrors = platformHandler;

        if (platformHandler) {
          PlatformDispatcher.instance.onError = (error, stack) {
            upstreamCalls++;
            return true;
          };
        } else {
          FlutterError.onError = (details) => upstreamCalls++;
        }
        integration = TxlemetryErrorTrackingAutoCaptureIntegration.install(
          config: config,
          txlemetry: txlemetry,
        )!;

        if (platformHandler) {
          final previous = PlatformDispatcher.instance.onError!;
          PlatformDispatcher.instance.onError = (error, stack) {
            if (++wrapperCalls > 1) {
              throw StateError('handler chain recursed');
            }
            return previous(error, stack);
          };
          dispatch = () => PlatformDispatcher.instance.onError!(
                StateError('handler lifecycle repro'),
                StackTrace.current,
              );
        } else {
          final previous = FlutterError.onError!;
          FlutterError.onError = (details) {
            if (++wrapperCalls > 1) {
              throw StateError('handler chain recursed');
            }
            previous(details);
          };
          dispatch = () {
            FlutterError.onError!(FlutterErrorDetails(
              exception: StateError('handler lifecycle repro'),
              stack: StackTrace.current,
            ));
            return true;
          };
        }
      });

      tearDown(() {
        TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();
        FlutterError.onError = savedFlutterHandler;
        PlatformDispatcher.instance.onError = savedPlatformHandler;
      });

      test('installed handler captures once and preserves the upstream chain',
          () {
        final handled = dispatch();

        expect(txlemetry.capturedExceptions, hasLength(1));
        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });

      test('uninstall restores a null upstream handler', () {
        TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();
        if (platformHandler) {
          PlatformDispatcher.instance.onError = null;
        } else {
          FlutterError.onError = null;
        }
        TxlemetryErrorTrackingAutoCaptureIntegration.install(
          config: config,
          txlemetry: txlemetry,
        );

        final handled = dispatch();
        expect(txlemetry.capturedExceptions, hasLength(1));
        if (platformHandler) expect(handled, isFalse);

        TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();

        expect(
          platformHandler
              ? PlatformDispatcher.instance.onError
              : FlutterError.onError,
          isNull,
        );
      });

      test('uninstall preserves the upstream handler chain', () {
        TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();

        final handled = dispatch();

        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });

      test('uninstall stops captures from a retained handler', () {
        TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();

        dispatch();

        expect(txlemetry.capturedExceptions, isEmpty);
      });

      test('restart captures once without a circular handler chain', () {
        integration.stop();
        integration.start();

        final handled = dispatch();

        expect(txlemetry.capturedExceptions, hasLength(1));
        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });

      test('repeated reinstalls leave only the current integration capturing',
          () {
        final retiredPlatforms = [txlemetry];
        for (var i = 0; i < 3; i++) {
          TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();
          txlemetry = TxlemetryFlutterPlatformFake();
          TxlemetryErrorTrackingAutoCaptureIntegration.install(
            config: config,
            txlemetry: txlemetry,
          );
          if (i < 2) retiredPlatforms.add(txlemetry);
        }

        final handled = dispatch();

        expect(txlemetry.capturedExceptions, hasLength(1));
        for (final retired in retiredPlatforms) {
          expect(retired.capturedExceptions, isEmpty);
        }
        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });

      test('reinstall captures once and preserves the upstream chain', () {
        TxlemetryErrorTrackingAutoCaptureIntegration.uninstall();
        TxlemetryErrorTrackingAutoCaptureIntegration.install(
          config: config,
          txlemetry: txlemetry,
        );

        final handled = dispatch();

        expect(txlemetry.capturedExceptions, hasLength(1));
        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });
    });
  }
}
