import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/txlemetry_config.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('txlemetry_flutter');
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('screen name argument wins over a properties \$screen_name', () async {
    final txlemetry = TxlemetryFlutterIO();
    await txlemetry.setup(TxlemetryConfig('test_token'));

    await txlemetry.screen(
      screenName: 'Checkout',
      properties: {
        '\$screen_name': 'From properties',
        'plan': 'pro',
      },
    );

    final call = log.firstWhere((c) => c.method == 'screen');
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final properties = Map<String, dynamic>.from(args['properties'] as Map);

    expect(args['screenName'], 'Checkout');
    expect(properties.containsKey('\$screen_name'), isFalse);
    expect(properties['plan'], 'pro');
  });
}
