import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TxlemetryFlutterPlatformFake platform;
  FlutterExceptionHandler? originalFlutterHandler;
  ErrorCallback? originalPlatformHandler;

  setUp(() async {
    platform = TxlemetryFlutterPlatformFake();
    TxlemetryFlutterPlatformInterface.instance = platform;
    await Txlemetry().close();
    originalFlutterHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
    if (!kIsWeb) {
      originalPlatformHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (_, __) => true;
    }
  });

  tearDown(() async {
    await Txlemetry().close();
    FlutterError.onError = originalFlutterHandler;
    if (!kIsWeb) {
      PlatformDispatcher.instance.onError = originalPlatformHandler;
    }
  });

  void reportFlutterError({bool silent = false}) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: StateError('repeated setup repro'),
      stack: StackTrace.current,
      silent: silent,
    ));
  }

  for (final reuseConfig in [false, true]) {
    test('disables Flutter hook on repeated setup (reuse=$reuseConfig)',
        () async {
      final upstream = FlutterError.onError;
      final first = TxlemetryConfig('test-token')
        ..errorTrackingConfig.captureFlutterErrors = true;
      await Txlemetry().setup(first);
      reportFlutterError();
      expect(platform.capturedExceptions, hasLength(1));
      platform.capturedExceptions.clear();

      final second = reuseConfig ? first : TxlemetryConfig('test-token');
      second.errorTrackingConfig.captureFlutterErrors = false;
      await Txlemetry().setup(second);
      expect(Txlemetry().config, same(second));

      reportFlutterError();
      expect(platform.capturedExceptions, isEmpty);
      expect(FlutterError.onError, same(upstream));
    });
  }

  test('disables PlatformDispatcher hook on repeated setup', () async {
    final upstream = PlatformDispatcher.instance.onError;
    final first = TxlemetryConfig('test-token')
      ..errorTrackingConfig.capturePlatformDispatcherErrors = true;
    await Txlemetry().setup(first);
    PlatformDispatcher.instance.onError!(
        StateError('before'), StackTrace.current);
    expect(platform.capturedExceptions, hasLength(1));
    platform.capturedExceptions.clear();

    await Txlemetry().setup(TxlemetryConfig('test-token'));
    PlatformDispatcher.instance.onError!(
        StateError('after'), StackTrace.current);
    expect(platform.capturedExceptions, isEmpty);
    expect(PlatformDispatcher.instance.onError, same(upstream));
  }, skip: kIsWeb);

  test('adds PlatformDispatcher hook while Flutter hook is installed',
      () async {
    final first = TxlemetryConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true;
    await Txlemetry().setup(first);

    final second = TxlemetryConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true
      ..errorTrackingConfig.capturePlatformDispatcherErrors = true;
    await Txlemetry().setup(second);
    expect(Txlemetry().config, same(second));

    PlatformDispatcher.instance.onError!(
        StateError('after'), StackTrace.current);
    expect(platform.capturedExceptions, hasLength(1));
  }, skip: kIsWeb);

  test('replaces silent-error policy on repeated setup', () async {
    final first = TxlemetryConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true;
    await Txlemetry().setup(first);

    final second = TxlemetryConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true
      ..errorTrackingConfig.captureSilentFlutterErrors = true;
    await Txlemetry().setup(second);

    reportFlutterError(silent: true);
    expect(platform.capturedExceptions, hasLength(1));
  });

  test('mutating the original silent-error policy takes effect', () async {
    final config = TxlemetryConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true;
    await Txlemetry().setup(config);
    config.errorTrackingConfig.captureSilentFlutterErrors = true;
    await Txlemetry().setup(config);

    reportFlutterError(silent: true);
    expect(platform.capturedExceptions, hasLength(1));
  });

  test('first installation can happen on second setup', () async {
    await Txlemetry().setup(TxlemetryConfig('test-token'));
    await Txlemetry().setup(TxlemetryConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true);

    reportFlutterError();
    expect(platform.capturedExceptions, hasLength(1));
  });

  test('identical repeated setup does not duplicate capture', () async {
    final config = TxlemetryConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true;
    await Txlemetry().setup(config);
    await Txlemetry().setup(config);

    reportFlutterError();
    expect(platform.capturedExceptions, hasLength(1));
  });

  for (final platformHandler in [false, true]) {
    test(
        'repeated setup preserves wrapped handlers (platform=$platformHandler)',
        () async {
      var upstreamCalls = 0;
      var wrapperCalls = 0;
      final config = TxlemetryConfig('test-token')
        ..errorTrackingConfig.captureFlutterErrors = !platformHandler
        ..errorTrackingConfig.capturePlatformDispatcherErrors = platformHandler;

      if (platformHandler) {
        PlatformDispatcher.instance.onError = (_, __) {
          upstreamCalls++;
          return true;
        };
      } else {
        FlutterError.onError = (_) => upstreamCalls++;
      }
      await Txlemetry().setup(config);
      if (platformHandler) {
        final delegate = PlatformDispatcher.instance.onError!;
        PlatformDispatcher.instance.onError = (error, stack) {
          wrapperCalls++;
          return delegate(error, stack);
        };
      } else {
        final delegate = FlutterError.onError!;
        FlutterError.onError = (details) {
          wrapperCalls++;
          delegate(details);
        };
      }

      for (var i = 0; i < 3; i++) {
        await Txlemetry().setup(config);
      }
      if (platformHandler) {
        expect(
          PlatformDispatcher.instance.onError!(
              StateError('after'), StackTrace.current),
          isTrue,
        );
      } else {
        reportFlutterError();
      }
      expect(platform.capturedExceptions, hasLength(1));
      expect(upstreamCalls, 1);
      expect(wrapperCalls, 1);
    }, skip: kIsWeb && platformHandler);
  }

  test('close then setup applies changed hook flags', () async {
    await Txlemetry().setup(TxlemetryConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true);
    await Txlemetry().close();
    await Txlemetry().setup(TxlemetryConfig('test-token')
      ..errorTrackingConfig.capturePlatformDispatcherErrors = true);

    reportFlutterError();
    expect(platform.capturedExceptions, isEmpty);
    PlatformDispatcher.instance.onError!(
        StateError('after'), StackTrace.current);
    expect(platform.capturedExceptions, hasLength(1));
  }, skip: kIsWeb);
}
