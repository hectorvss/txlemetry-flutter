import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/core/file_storage.dart';
import 'package:txlemetry_flutter/src/txlemetry_config.dart';
import 'package:txlemetry_flutter/src/txlemetry_desktop_client.dart';

import '../txlemetry_api_fake.dart';
import 'test_client.dart';

void main() {
  late Directory dir;
  late LocalTxlemetryServer server;

  setUp(() async {
    dir = tempDirectory();
    server = await LocalTxlemetryServer.start();
  });

  DesktopTxlemetry client({TxlemetryConfig? config}) =>
      testClient(server, config: config, storage: FileStorage(dir.path));

  test('queueing an event writes one file and rewrites nothing else', () async {
    final txlemetry = client();
    txlemetry.identify('user-1');
    txlemetry.capture('first');
    // Waits for the flags reload identify() started, which stores its answer.
    await txlemetry.reloadFeatureFlagsAsync();
    final snapshot = File('${dir.path}/posthog_data.json');
    final earlier = DateTime(2000);
    for (final file in [snapshot, ..._queueFiles(dir)]) {
      file.setLastModifiedSync(earlier);
    }

    txlemetry.capture('second');

    expect(snapshot.lastModifiedSync(), earlier);
    final files = _queueFiles(dir);
    expect([for (final file in files) _eventOf(file)],
        [r'$identify', 'first', 'second']);
    expect(files.where((file) => file.lastModifiedSync() != earlier),
        hasLength(1));
  });

  test('keeps the queue order across a restart', () async {
    final before = client();
    for (var i = 0; i < 50; i++) {
      before.capture('event_$i');
    }
    before.close();

    await client().flush();

    expect(server.eventNames, [for (var i = 0; i < 50; i++) 'event_$i']);
    expect(_queueFiles(dir), isEmpty);
  });

  test('drops the oldest event files once the queue is full', () {
    final api = InProcessTxlemetryApi()
      ..respond = (_) => const TxlemetryResponse.dropped();
    fakeAsync((async) {
      final txlemetry = testClient(api,
          config: testConfig(flushAt: 2, maxQueueSize: 2),
          storage: FileStorage(dir.path));

      for (final event in ['first', 'second', 'third']) {
        txlemetry.capture(event);
      }
      async.elapse(Duration.zero);

      expect([for (final file in _queueFiles(dir)) _eventOf(file)],
          ['second', 'third']);
    });
  });

  test('limits the restored queue before the first timer without capture', () {
    final before = client();
    for (var i = 0; i < 5; i++) {
      before.capture('event_$i');
    }
    final original = [
      for (final file in _queueFiles(dir).skip(3))
        jsonDecode(file.readAsStringSync()),
    ];
    before.close();

    final api = InProcessTxlemetryApi();
    fakeAsync((async) {
      testClient(api,
          config: testConfig(maxQueueSize: 2, flushAt: 1),
          storage: FileStorage(dir.path));
      expect([for (final file in _queueFiles(dir)) _eventOf(file)],
          ['event_3', 'event_4']);
      expect(api.requests, isEmpty);
      async.elapse(const Duration(seconds: 30));
      expect(api.batchRequests.single.events, original);
      expect(_queueFiles(dir), isEmpty);
    });
  });

  for (final (capacity, remaining) in [(5, 3), (3, 3), (0, 1)]) {
    test('restores $remaining events with maxQueueSize $capacity', () async {
      final before = client();
      for (var i = 0; i < 3; i++) {
        before.capture('event_$i');
      }
      before.close();
      await client(config: testConfig(maxQueueSize: capacity)).flush();
      expect(server.eventNames,
          [for (var i = 3 - remaining; i < 3; i++) 'event_$i']);
    });
  }

  test('restoring a secondary queue does not remove primary queue events',
      () async {
    final primary = client();
    primary.capture('first');
    primary.capture('second');
    final secondary = client(config: testConfig(maxQueueSize: 1));
    secondary.capture('secondary');
    await secondary.flush();
    expect([for (final file in _queueFiles(dir)) _eventOf(file)],
        ['first', 'second']);
    await primary.flush();
    expect(server.eventNames, ['secondary', 'first', 'second']);
  });

  test('deletes a queued event that cannot be read and sends the others',
      () async {
    final before = client();
    for (final event in ['first', 'second', 'third']) {
      before.capture(event);
    }
    before.close();
    final corrupt = _queueFiles(dir)[1]..writeAsStringSync('{"event": "sec');

    final after = client(config: testConfig(debug: true));
    late Future<void> flushed;
    final lines = printedLines(() => flushed = after.flush());
    await flushed;

    expect(server.eventNames, ['first', 'third']);
    expect(lines, contains(contains('cannot be read')));
    expect(corrupt.existsSync(), isFalse);
  });

  test("two clients on one directory never delete each other's events",
      () async {
    final first = client();
    final second = client();

    first.capture('from first');
    second.capture('from second');
    await first.flush();

    expect(server.eventNames, ['from first']);
    expect(
        [for (final file in _queueFiles(dir)) _eventOf(file)], ['from second']);
  });

  test('an event whose file cannot be written is still sent', () async {
    addTearDown(() => chmod('755', dir.path));
    final txlemetry = client();
    chmod('555', dir.path);

    txlemetry.capture('evt');
    await txlemetry.flush();

    expect(server.eventNames, ['evt']);
    expect(Directory('${dir.path}/posthog_queue').existsSync(), isFalse);
  }, skip: chmodSkip);
}

/// The event files of the queue in [dir], oldest first.
List<File> _queueFiles(Directory dir) {
  final queue = Directory('${dir.path}/posthog_queue');
  if (!queue.existsSync()) return [];
  return queue.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

Object? _eventOf(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map)['event'];
