import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_data.dart';
import 'package:txlemetry_flutter/src/replay/mask/txlemetry_mask_controller.dart';

void main() {
  Widget appWithContainerKey() {
    return MaterialApp(
      home: RepaintBoundary(
        key: TxlemetryMaskController.instance.containerKey,
        child: Scaffold(
          body: Column(
            children: [
              const Text('visible text'),
              TxlemetryMaskWidget(child: const Text('wrapped')),
              const TextField(obscureText: true),
            ],
          ),
        ),
      ),
    );
  }

  Set<String> describe(List<ElementData> elements) {
    return elements.map((e) => '${e.type}:${e.rect}').toSet();
  }

  testWidgets('getMaskElements with all widgets matches the two-walk union',
      (tester) async {
    await tester.pumpWidget(appWithContainerKey());

    final combined =
        TxlemetryMaskController.instance.getMaskElements(includeAllWidgets: true);
    final wrapperOnly =
        TxlemetryMaskController.instance.getTxlemetryWidgetWrapperElements();
    final allWidgets =
        TxlemetryMaskController.instance.getCurrentWidgetsElements();

    expect(combined, isNotNull);
    expect(
      describe(combined!),
      describe([...wrapperOnly!, ...allWidgets!]),
    );
    expect(combined, isNotEmpty);
  });

  testWidgets('getMaskElements without all widgets matches the wrapper walk',
      (tester) async {
    await tester.pumpWidget(appWithContainerKey());

    final combined = TxlemetryMaskController.instance
        .getMaskElements(includeAllWidgets: false);
    final wrapperOnly =
        TxlemetryMaskController.instance.getTxlemetryWidgetWrapperElements();

    expect(combined, isNotNull);
    expect(describe(combined!), describe(wrapperOnly!));
  });

  test('getMaskElements returns null without a mounted container', () {
    expect(
      TxlemetryMaskController.instance.getMaskElements(includeAllWidgets: true),
      isNull,
    );
  });

  test('refreshParsers rebuilds the parser map from the new config', () {
    final controller = TxlemetryMaskController.instance;
    addTearDown(() => controller.refreshParsers(null));

    final textsOnly = TxlemetryConfig('phc_test').sessionReplayConfig
      ..maskAllImages = false;
    controller.refreshParsers(textsOnly);
    expect(controller.parsers.keys, isNot(contains('RenderImage')));
    expect(controller.parsers.keys, contains('RenderParagraph'));

    final imagesToo = TxlemetryConfig('phc_test').sessionReplayConfig;
    controller.refreshParsers(imagesToo);
    expect(controller.parsers.keys, contains('RenderImage'));
  });
}
