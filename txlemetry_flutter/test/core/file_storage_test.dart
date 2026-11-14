import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/core/file_storage.dart';
import 'package:txlemetry_flutter/src/core/logger.dart';
import 'package:txlemetry_flutter/src/core/persistence.dart';

import '../txlemetry_api_fake.dart';
import 'test_client.dart';

void main() {
  group('FileStorage', () {
    test('memory storage keeps consent and queued events without disk IO', () {
      IOOverrides.runZoned(() {
        final storage = FileStorage.memory();
        storage.setProperty(TxlemetryPersistedProperty.optedOut, true);
        storage.queue.add({'event': 'captured'});

        expect(storage.getProperty<bool>(TxlemetryPersistedProperty.optedOut),
            isTrue);
        final queued = storage.queue.peek(1).single;
        expect(queued.event['event'], 'captured');
        storage.queue.removeOldest(1);
        storage.queue.remove([queued.id]);
        expect(storage.queue.length, 0);
        storage.close();
      },
          createFile: (_) => throw StateError('Unexpected file access'),
          createDirectory: (_) =>
              throw StateError('Unexpected directory access'));
    });

    test('setting a property to null removes it from the persisted snapshot',
        () {
      final dir = Directory.systemTemp.createTempSync('txlemetry_storage_null');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = FileStorage(dir.path);
      addTearDown(storage.close);
      storage.setProperty(TxlemetryPersistedProperty.distinctId, 'user-1');
      storage.setProperty(TxlemetryPersistedProperty.anonymousId, 'anon-1');

      storage.setProperty(TxlemetryPersistedProperty.distinctId, null);

      final reopened = FileStorage(dir.path);
      addTearDown(reopened.close);
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          isNull);
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.anonymousId),
          'anon-1');
    });

    test('reads a stored value of an unexpected type as null', () {
      final dir = Directory.systemTemp.createTempSync('txlemetry_storage_type');
      addTearDown(() => dir.deleteSync(recursive: true));

      final storage = FileStorage(dir.path);
      addTearDown(storage.close);
      storage.setProperty<Object>(TxlemetryPersistedProperty.props, 'garbage');

      final reopened = FileStorage(dir.path);
      addTearDown(reopened.close);
      expect(
          reopened.getProperty<Map<String, Object?>>(
              TxlemetryPersistedProperty.props),
          isNull);
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.props),
          'garbage');
    });

    test('drops a value that cannot be JSON-encoded', () {
      final dir = Directory.systemTemp.createTempSync('txlemetry_storage');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = FileStorage(dir.path);
      addTearDown(storage.close);

      storage.setProperty(
          TxlemetryPersistedProperty.props, {'date': DateTime.now()});

      expect(
          storage.getProperty<Map<String, Object?>>(
              TxlemetryPersistedProperty.props),
          isNull,
          reason: 'a value the snapshot cannot serialize must not stay in '
              'the cache, or every later write would fail');

      // The store keeps working after the rejected write.
      storage.setProperty(TxlemetryPersistedProperty.distinctId, 'id-1');
      final reopened = FileStorage(dir.path);
      addTearDown(reopened.close);
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          'id-1');
    });

    // (description, on-disk bytes)
    final utf8Corruptions = <(String, List<int>)>[
      (
        'a multi-byte character truncated by a torn write',
        [0x7b, 0x22, 0xd0],
      ),
      (
        // {"distinct_id":"a<0xD0>b"}: the JSON structure is intact, but the
        // continuation-less byte fails strict UTF-8 decoding.
        'an invalid byte inside a string value',
        [...'{"distinct_id":"a'.codeUnits, 0xd0, ...'b"}'.codeUnits],
      ),
    ];

    for (final (description, bytes) in utf8Corruptions) {
      test('resets the store when the file holds $description', () {
        final dir = Directory.systemTemp.createTempSync('txlemetry_storage_utf8');
        addTearDown(() => dir.deleteSync(recursive: true));
        File('${dir.path}/posthog_data.json').writeAsBytesSync(bytes);

        final storage = FileStorage(dir.path);
        addTearDown(storage.close);
        expect(storage.isDegraded, isFalse);
        expect(storage.getProperty<String>(TxlemetryPersistedProperty.distinctId),
            isNull,
            reason: 'corrupt bytes must reset the store, not brick it or '
                'resurrect mangled values via lenient decoding');

        // Self-heal: the next write persists a fresh valid snapshot.
        storage.setProperty(TxlemetryPersistedProperty.distinctId, 'healed');
        final reopened = FileStorage(dir.path);
        addTearDown(reopened.close);
        expect(
            reopened.getProperty<String>(TxlemetryPersistedProperty.distinctId),
            'healed');
      });
    }

    // (description, on-disk content)
    const corruptContents = <(String, String)>[
      ('an empty file', ''),
      ('a JSON string', '"txlemetry"'),
      ('a JSON array', '[1, 2]'),
      ('truncated JSON', '{"distinct_id":'),
    ];

    for (final (description, content) in corruptContents) {
      test('resets a store holding $description and heals on the next write',
          () {
        final dir = Directory.systemTemp.createTempSync('txlemetry_storage_bad');
        addTearDown(() => dir.deleteSync(recursive: true));
        File('${dir.path}/posthog_data.json').writeAsStringSync(content);

        final storage = FileStorage(dir.path);
        addTearDown(storage.close);
        expect(storage.isDegraded, isFalse);
        expect(storage.getProperty<String>(TxlemetryPersistedProperty.distinctId),
            isNull);

        storage.setProperty(TxlemetryPersistedProperty.distinctId, 'healed');
        final reopened = FileStorage(dir.path);
        addTearDown(reopened.close);
        expect(
            reopened.getProperty<String>(TxlemetryPersistedProperty.distinctId),
            'healed');
      });
    }

    test('a failed write keeps the value in memory and does not throw', () {
      final dir = Directory.systemTemp.createTempSync('txlemetry_storage_ro');
      addTearDown(() {
        chmod('755', dir.path);
        dir.deleteSync(recursive: true);
      });
      final storage = FileStorage(dir.path);
      addTearDown(storage.close);
      storage.setProperty(TxlemetryPersistedProperty.distinctId, 'a');

      // Snapshots go through tmp+rename, so blocking the write means
      // removing write permission from the directory, not the file.
      chmod('555', dir.path);

      expect(
          () => storage.setProperty(TxlemetryPersistedProperty.distinctId, 'b'),
          returnsNormally);
      expect(storage.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          'b');

      chmod('755', dir.path);
      storage.setProperty(TxlemetryPersistedProperty.anonymousId, 'anon');
      // The next successful write persists the whole snapshot, 'b' included.
      final reopened = FileStorage(dir.path);
      addTearDown(reopened.close);
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          'b');
    }, skip: chmodSkip);

    test('a failed write leaves the on-disk snapshot untouched', () {
      final dir = Directory.systemTemp.createTempSync('txlemetry_storage_disk');
      addTearDown(() {
        chmod('755', dir.path);
        dir.deleteSync(recursive: true);
      });
      final storage = FileStorage(dir.path);
      addTearDown(storage.close);
      storage.setProperty(TxlemetryPersistedProperty.distinctId, 'a');

      chmod('555', dir.path);
      storage.setProperty(TxlemetryPersistedProperty.distinctId, 'b');

      final reopened = FileStorage(dir.path);
      addTearDown(reopened.close);
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          'a',
          reason: 'the data file itself stayed writable, so an in-place '
              'write (instead of tmp+rename) would have replaced the good '
              'snapshot');
    }, skip: chmodSkip);

    test('reports a failed write to its logger', () {
      final dir = Directory.systemTemp.createTempSync('txlemetry_storage_log');
      addTearDown(() {
        chmod('755', dir.path);
        dir.deleteSync(recursive: true);
      });
      final storage = FileStorage(dir.path)
        ..logger = CoreLogger((log) => log());
      addTearDown(storage.close);
      storage.setProperty(TxlemetryPersistedProperty.distinctId, 'a');
      chmod('555', dir.path);

      final lines = printedLines(
          () => storage.setProperty(TxlemetryPersistedProperty.distinctId, 'b'));

      expect(lines, [contains('Failed to persist')]);
    }, skip: chmodSkip);

    for (final debug in [true, false]) {
      test('corrupt snapshot warnings omit stored values with debug: $debug',
          () async {
        final server = await LocalTxlemetryServer.start();
        final dir = tempDirectory();
        File('${dir.path}/posthog_data.json').writeAsStringSync(
          '{"distinct_id":"private-user","props":{"email":"private@example.com"}',
        );

        final lines = printedLines(() => testClient(server,
            config: testConfig(debug: debug), storage: FileStorage(dir.path)));

        expect(lines.where((line) => line.contains('Resetting')), hasLength(1));
        expect(lines.join('\n'), isNot(contains('private-user')));
        expect(lines.join('\n'), isNot(contains('private@example.com')));
      });

      test('a client with debug: $debug reports write failures accordingly',
          () async {
        final server = await LocalTxlemetryServer.start();
        final dir = Directory.systemTemp.createTempSync('txlemetry_client_log');
        addTearDown(() {
          chmod('755', dir.path);
          dir.deleteSync(recursive: true);
        });
        final client = testClient(server,
            config: testConfig(debug: debug), storage: FileStorage(dir.path));
        chmod('555', dir.path);

        final lines = printedLines(() => client.capture('evt'));

        expect(lines.where((line) => line.contains('Failed to persist')),
            debug ? isNotEmpty : isEmpty);
      }, skip: chmodSkip);
    }

    test('an unreadable snapshot keeps the instance in memory, disk intact',
        () {
      final dir = Directory.systemTemp.createTempSync('txlemetry_storage_rd');
      final dataFile = '${dir.path}/posthog_data.json';
      addTearDown(() {
        chmod('644', dataFile);
        dir.deleteSync(recursive: true);
      });
      final storage = FileStorage(dir.path);
      addTearDown(storage.close);
      storage
        ..setProperty(TxlemetryPersistedProperty.distinctId, 'keep')
        ..setProperty(TxlemetryPersistedProperty.anonymousId, 'anon')
        ..close();

      chmod('000', dataFile);

      final blind = FileStorage(dir.path)..logger = CoreLogger((log) => log());
      addTearDown(blind.close);
      expect(blind.isDegraded, isTrue);
      final lines = printedLines(() =>
          blind.setProperty(TxlemetryPersistedProperty.distinctId, 'in-memory'));
      expect(blind.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          'in-memory',
          reason: 'the running client must stay consistent, e.g. keep one '
              'anonymous id instead of generating one per read');
      expect(lines, [contains('in memory only')]);

      chmod('644', dataFile);
      expect(blind.isDegraded, isTrue,
          reason: 'mixing a snapshot whose contents were unknown with '
              'runtime writes could restore stale identity and consent');
      expect(blind.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          'in-memory');
      expect(blind.getProperty<String>(TxlemetryPersistedProperty.anonymousId),
          isNull);

      final reopened = FileStorage(dir.path);
      addTearDown(reopened.close);
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          'keep');
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.anonymousId),
          'anon');
    }, skip: chmodSkip);

    test('an unreadable directory reads as degraded, not as a fresh store', () {
      final dir = Directory.systemTemp.createTempSync('txlemetry_storage_dir');
      final sub = Directory('${dir.path}/store')..createSync();
      addTearDown(() {
        chmod('755', sub.path);
        dir.deleteSync(recursive: true);
      });
      final storage = FileStorage(sub.path);
      addTearDown(storage.close);
      storage.setProperty(TxlemetryPersistedProperty.distinctId, 'keep');

      chmod('000', sub.path);

      final blind = FileStorage(sub.path);
      addTearDown(blind.close);
      expect(blind.isDegraded, isTrue);
      expect(blind.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          isNull);

      chmod('755', sub.path);
      expect(blind.isDegraded, isTrue);
      expect(blind.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          isNull);

      final reopened = FileStorage(sub.path);
      addTearDown(reopened.close);
      expect(reopened.getProperty<String>(TxlemetryPersistedProperty.distinctId),
          'keep');
    }, skip: chmodSkip);
  });
}
