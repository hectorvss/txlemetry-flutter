import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/txlemetry_config.dart';

import '../txlemetry_api_fake.dart';
import 'test_client.dart';

void main() {
  for (final compression in TxlemetryCompression.values) {
    test('${compression.name} applies to batches and flags', () async {
      final server = await LocalTxlemetryServer.start();
      final client =
          testClient(server, config: testConfig()..compression = compression);

      client.capture('desktop_event', properties: {'source': 'test'});
      await client.flush();
      await client.reloadFeatureFlagsAsync();

      expect(server.batchRequests.single.eventNames, ['desktop_event']);
      expect(server.flagsRequests, hasLength(1));
      for (final request in server.requests) {
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['content-encoding'],
            compression == TxlemetryCompression.gzip ? 'gzip' : isNull);
        expect(request.body['api_key'] ?? request.body['token'], 'k');
      }
    });
  }
}
