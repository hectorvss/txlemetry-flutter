import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('txlemetry_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterPlatformFake();
    await Txlemetry().close();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSessionReplayState') {
        return {'isActive': false, 'sessionId': null};
      }
      return null;
    });
  });

  tearDown(() async {
    await Txlemetry().close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<List<String?>> recordDebugPrint(Future<void> Function() action) async {
    final messages = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => messages.add(message);
    try {
      await action();
    } finally {
      debugPrint = originalDebugPrint;
    }
    return messages;
  }

  testWidgets('mounting before setup warns once on native and not on web',
      (tester) async {
    final messages = await recordDebugPrint(() async {
      await tester.pumpWidget(const TxlemetryWidget(child: SizedBox()));
      final state = tester.state(find.byType(TxlemetryWidget));
      await tester.pumpWidget(const TxlemetryWidget(child: SizedBox.expand()));
      expect(tester.state(find.byType(TxlemetryWidget)), same(state));
      await tester.pumpWidget(const SizedBox());
    });

    expect(
      messages,
      kIsWeb
          ? isEmpty
          : equals([
              '[Txlemetry] TxlemetryWidget mounted before Txlemetry().setup(). '
                  'If you intend to use mobile session replay, call setup() before runApp(), '
                  'or remount TxlemetryWidget after setup(). '
                  'Otherwise, you can ignore this message.',
            ]),
    );
  });

  for (final sessionReplay in [false, true]) {
    testWidgets('setup before mounting does not warn (replay: $sessionReplay)',
        (tester) async {
      await Txlemetry().setup(
          TxlemetryConfig('test_project_token')..sessionReplay = sessionReplay);

      final messages = await recordDebugPrint(() async {
        await tester.pumpWidget(const TxlemetryWidget(child: SizedBox()));
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 1));
      });

      expect(messages, isEmpty);
    });
  }
}
