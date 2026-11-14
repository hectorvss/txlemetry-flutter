@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

void main() {
  test('repeated setup turns the isolate hook off and back on', () async {
    final results = ReceivePort();
    final isolate = await Isolate.spawn(
      _exerciseIsolateHook,
      results.sendPort,
      errorsAreFatal: false,
      onExit: results.sendPort,
    );
    addTearDown(() {
      isolate.kill(priority: Isolate.immediate);
      results.close();
    });

    expect(await results.first, [1, 0, 1]);
  });
}

Future<void> _exerciseIsolateHook(SendPort results) async {
  final observedErrors = ReceivePort();
  final errors = StreamIterator<dynamic>(observedErrors);
  Isolate.current.addErrorListener(observedErrors.sendPort);
  final platform = TxlemetryFlutterPlatformFake();
  TxlemetryFlutterPlatformInterface.instance = platform;

  try {
    final counts = <int>[];
    for (final enabled in [true, false, true]) {
      await Txlemetry().setup(TxlemetryConfig('test-token')
        ..errorTrackingConfig.captureIsolateErrors = enabled);
      platform.capturedExceptions.clear();
      Timer.run(() => throw StateError('isolate hook enabled=$enabled'));
      await errors.moveNext();
      // Error listeners use separate ports; let the SDK's queued callback run.
      await Future<void>.delayed(Duration.zero);
      counts.add(platform.capturedExceptions.length);
    }
    results.send(counts);
  } catch (error, stack) {
    results.send('$error\n$stack');
  } finally {
    await Txlemetry().close();
    Isolate.current.removeErrorListener(observedErrors.sendPort);
    await errors.cancel();
    observedErrors.close();
  }
}
