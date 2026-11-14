import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_io.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';
import 'package:txlemetry_flutter/src/txlemetry_internal_events.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('txlemetry_flutter');
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterIO();
    await Txlemetry().close();
    calls.clear();
  });

  tearDown(() async {
    await Txlemetry().close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('touch capture defaults to enabled in the native setup map', () {
    expect(TxlemetrySessionReplayConfig().toMap()['captureTouches'], isTrue);
  });

  test('setup forwards disabled touch capture without disabling replay',
      () async {
    final config = TxlemetryConfig('test-token')
      ..sessionReplay = true
      ..sessionReplayConfig.captureTouches = false;
    await Txlemetry().setup(config);

    final setup = calls.singleWhere((call) => call.method == 'setup');
    final arguments = setup.arguments as Map<Object?, Object?>;
    final replayConfig =
        arguments['sessionReplayConfig'] as Map<Object?, Object?>;
    expect(arguments['sessionReplay'], isTrue);
    expect(replayConfig['captureTouches'], isFalse);
    expect(TxlemetryInternalEvents.sessionRecordingActive.value, isTrue);
  });

  test('a fresh setup after close restores the default touch setting',
      () async {
    await Txlemetry().setup(TxlemetryConfig('test-token')
      ..sessionReplayConfig.captureTouches = false);
    await Txlemetry().close();
    calls.clear();
    await Txlemetry().setup(TxlemetryConfig('test-token'));

    final setup = calls.singleWhere((call) => call.method == 'setup');
    final arguments = setup.arguments as Map<Object?, Object?>;
    final replayConfig =
        arguments['sessionReplayConfig'] as Map<Object?, Object?>;
    expect(replayConfig['captureTouches'], isTrue);
  });
}
