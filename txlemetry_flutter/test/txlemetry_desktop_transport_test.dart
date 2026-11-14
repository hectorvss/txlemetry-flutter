import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_desktop_app_info.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_desktop.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_version.dart';

import 'txlemetry_api_fake.dart';

class _DesktopTransportBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {}

void main() {
  _DesktopTransportBinding();

  late Directory appDirectory;
  late LocalTxlemetryServer server;
  late TxlemetryFlutterPlatformInterface previousPlatform;

  setUp(() async {
    appDirectory = Directory.systemTemp.createTempSync('txlemetry_transport');
    server = await LocalTxlemetryServer.start();
    previousPlatform = TxlemetryFlutterPlatformInterface.instance;
    TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterDesktop(
      appDirectory: () async => appDirectory.path,
      appInfo: const DesktopAppInfo(
        name: 'transport_test',
        version: '1.2.3',
        build: '42',
      ),
      timezone: 'Europe/Berlin',
    );
  });

  tearDown(() async {
    await Txlemetry().close();
    TxlemetryFlutterPlatformInterface.instance = previousPlatform;
    if (appDirectory.existsSync()) appDirectory.deleteSync(recursive: true);
  });

  TxlemetryConfig config({int flushAt = 1}) => TxlemetryConfig('phc_transport')
    ..host = server.url
    ..flushAt = flushAt
    ..flushInterval = const Duration(hours: 1)
    ..captureApplicationLifecycleEvents = false;

  test('facade captures and honors consent without filesystem access',
      () async {
    TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterDesktop(
      appDirectory: () async => null,
      appInfo: const DesktopAppInfo(name: 'memory_test'),
      timezone: null,
    );
    await IOOverrides.runZoned(() async {
      await Txlemetry().setup(config()..preloadFeatureFlags = false);
      await Txlemetry().disable();
      expect(await Txlemetry().isOptOut(), isTrue);
      await Txlemetry().capture(eventName: 'blocked event');
      await Txlemetry().enable();
      await Txlemetry().capture(eventName: 'memory event');
      await Txlemetry().flush();
      expect(server.eventNames, ['memory event']);
    },
        createFile: (_) => throw StateError('Unexpected file access'),
        createDirectory: (_) =>
            throw StateError('Unexpected directory access'));
  });

  test('facade sends a gzipped batch with envelope and event metadata',
      () async {
    await Txlemetry().setup(config(flushAt: 2)..preloadFeatureFlags = false);

    await Txlemetry().capture(
      eventName: 'first event',
      properties: {'source': 'desktop'},
    );
    await Txlemetry().capture(eventName: 'second event');
    await server.waitForEvent('second event');

    final request = server.batchRequests.single;
    expect(request.headers['content-encoding'], 'gzip');
    expect(request.headers['content-type'], 'application/json');
    expect(request.body['api_key'], 'phc_transport');
    expect(DateTime.tryParse(request.body['sent_at']! as String), isNotNull);
    expect(request.eventNames, ['first event', 'second event']);

    for (final event in request.events) {
      expect(event['uuid'], isA<String>());
      expect(DateTime.tryParse(event['timestamp']! as String), isNotNull);
      expect(event['distinct_id'], isA<String>());
      final properties = Map<String, Object?>.from(event['properties']! as Map);
      expect(properties[r'$lib'], txlemetryFlutterSdkName);
      expect(properties[r'$device_type'], 'Desktop');
      expect(properties[r'$app_version'], '1.2.3');
      expect(properties[r'$app_build'], 42);
      expect(properties[r'$timezone'], 'Europe/Berlin');
    }
  });

  test('facade sends flag context and blocks capture while opted out',
      () async {
    server.respond = (request) => request.isFlags
        ? TxlemetryResponse.json({'flags': <String, Object?>{}})
        : const TxlemetryResponse(HttpStatus.ok);
    await Txlemetry().setup(config());

    final flags = await server.waitForFlagsRequest(0);
    final personProperties =
        Map<String, Object?>.from(flags['person_properties']! as Map);
    expect(flags['token'], 'phc_transport');
    expect(personProperties[r'$lib'], txlemetryFlutterSdkName);
    expect(personProperties[r'$lib_version'], txlemetryFlutterVersion);
    expect(personProperties[r'$device_type'], 'Desktop');
    expect(personProperties[r'$app_version'], '1.2.3');

    await Txlemetry().disable();
    expect(await Txlemetry().isOptOut(), isTrue);
    await Txlemetry().capture(eventName: 'blocked event');
    await Txlemetry().enable();
    await Txlemetry().capture(eventName: 'allowed event');
    await server.waitForEvent('allowed event');

    expect(server.eventNames, isNot(contains('blocked event')));
    expect(server.eventNames, contains('allowed event'));
  });
}
