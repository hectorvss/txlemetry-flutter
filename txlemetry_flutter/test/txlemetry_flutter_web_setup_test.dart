@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/txlemetry_flutter_web.dart';
import 'package:txlemetry_flutter/src/replay/web/web_canvas_mask_provider.dart';

/// txlemetry-js is initialized by the host app on web, so options the plugin
/// cannot forward must warn instead of silently doing nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(WebCanvasMaskProvider.resetForTesting);
  tearDown(WebCanvasMaskProvider.resetForTesting);

  Future<List<String>> setupCapturingLogs(TxlemetryConfig config) async {
    final logs = <String>[];
    await runZoned(
      () => TxlemetryFlutterWeb().setup(config),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => logs.add(line),
      ),
    );
    return logs;
  }

  test('warns that preloadFeatureFlags is not applied on web', () async {
    final config = TxlemetryConfig('test_project_token');
    config.preloadFeatureFlags = false;

    final logs = await setupCapturingLogs(config);

    final warnings =
        logs.where((line) => line.contains('preloadFeatureFlags')).toList();
    expect(warnings, hasLength(1));
    expect(warnings.single,
        contains('advanced_disable_feature_flags_on_first_load'));
  });

  test('does not warn when preloadFeatureFlags keeps its default', () async {
    final logs = await setupCapturingLogs(TxlemetryConfig('test_project_token'));

    expect(logs.where((line) => line.contains('preloadFeatureFlags')), isEmpty);
  });

  test('warns that bootstrap is not applied on web', () async {
    final config = TxlemetryConfig('test_project_token');
    config.bootstrap = TxlemetryBootstrapConfig(distinctId: 'user-1');

    final logs = await setupCapturingLogs(config);

    expect(logs.where((line) => line.contains('bootstrap')), hasLength(1));
  });
}
