import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_io.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';

import 'replay_capture_settle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('txlemetry_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late TxlemetryFlutterPlatformInterface previousPlatform;

  setUp(() {
    previousPlatform = TxlemetryFlutterPlatformInterface.instance;
    TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterIO();
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getSessionReplayState') {
        return {'isActive': true, 'sessionId': 'session-a'};
      }
      if (call.method == 'sendFullSnapshot') {
        throw PlatformException(code: 'channel', message: 'snapshot failed');
      }
      return null;
    });
  });

  tearDown(() async {
    await Txlemetry().close();
    messenger.setMockMethodCallHandler(channel, null);
    TxlemetryFlutterPlatformInterface.instance = previousPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a failed snapshot is sent again on the next tick',
      (tester) async {
    final config = TxlemetryConfig('test_project_token')
      ..sessionReplay = true
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;
    await Txlemetry().setup(config);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 101,
          height: 99,
          child: TxlemetryWidget(
            child: ColoredBox(color: Color(0xFF00FF00)),
          ),
        ),
      ),
    );

    await settleUntil(
      tester,
      () => calls.any((call) => call.method == 'sendFullSnapshot'),
    );
    // Let the in-flight send finish before the next poll, or that tick is
    // dropped because a capture is already running.
    await settleCapture(tester);
    expect(
      calls.where((call) => call.method == 'sendFullSnapshot'),
      hasLength(1),
    );

    // A static screen does not schedule its own frame, so the next poll's
    // callback waits until something else draws. The pixels are unchanged, so
    // a send that was marked delivered is not repeated.
    await tester.pump(const Duration(seconds: 1));
    WidgetsBinding.instance.scheduleFrame();
    await settleCapture(tester);

    expect(
      calls.where((call) => call.method == 'sendFullSnapshot').length,
      greaterThan(1),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
