@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';
import 'package:txlemetry_flutter/src/txlemetry_internal_events.dart';
import 'package:txlemetry_flutter/src/replay/mask/txlemetry_mask_controller.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

void main() {
  Future<void> setupTxlemetry() async {
    TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterPlatformFake();
    final config = TxlemetryConfig('test_project_token');
    config.sessionReplay = true;
    await Txlemetry().setup(config);
  }

  Future<void> pumpReplayWidget(WidgetTester tester) async {
    await tester.pumpWidget(
      TxlemetryWidget(child: Container(color: const Color(0xFF00FF00))),
    );
  }

  tearDown(() async {
    await Txlemetry().close();
  });

  group('TxlemetryWidget on web', () {
    testWidgets('does not start screenshot polling after mounting',
        (tester) async {
      await setupTxlemetry();
      final timers = <Duration>[];
      await runZoned(() => pumpReplayWidget(tester),
          zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          timers.add(duration);
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ));
      expect(timers, isEmpty);
    });

    testWidgets('stays idle when session recording turns active',
        (tester) async {
      await setupTxlemetry();
      await pumpReplayWidget(tester);

      final timers = <Duration>[];
      runZoned(() {
        TxlemetryInternalEvents.sessionRecordingActive.value = false;
        TxlemetryInternalEvents.sessionRecordingActive.value = true;
      }, zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          timers.add(duration);
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ));
      expect(timers, isEmpty);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('still mounts the mask controller container', (tester) async {
      await setupTxlemetry();
      await pumpReplayWidget(tester);

      expect(TxlemetryMaskController.instance.containerKey.currentContext,
          isNotNull);
    });
  });
}
