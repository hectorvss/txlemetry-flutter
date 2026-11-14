import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_data.dart';
import 'package:txlemetry_flutter/src/replay/mask/txlemetry_mask_controller.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

void main() {
  Future<void> setupTxlemetry({
    required bool maskAllTexts,
    required bool maskAllImages,
  }) async {
    TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterPlatformFake();
    final config = TxlemetryConfig('test_project_token');
    config.sessionReplayConfig.maskAllTexts = maskAllTexts;
    config.sessionReplayConfig.maskAllImages = maskAllImages;
    await Txlemetry().setup(config);
    // the controller singleton may have been created before this setup
    TxlemetryMaskController.instance.refreshParsers(config.sessionReplayConfig);
  }

  tearDown(() async {
    TxlemetryMaskController.instance.refreshParsers(null);
    await Txlemetry().close();
  });

  Future<void> pumpTree(WidgetTester tester) async {
    // real async work: it never completes inside the test's FakeAsync zone
    final ui.Image image = (await tester.runAsync(
      () => createTestImage(width: 20, height: 20),
    ))!;
    addTearDown(image.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: TxlemetryMaskController.instance.containerKey,
          child: Scaffold(
            body: Column(
              children: [
                const Text('some text'),
                RawImage(image: image, width: 20, height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Set<String> types(List<ElementData> elements) =>
      elements.map((e) => e.type).toSet();

  testWidgets(
      'maskAllTexts=false keeps Text out of the mask set even when '
      'maskAllImages is on', (tester) async {
    await setupTxlemetry(maskAllTexts: false, maskAllImages: true);
    await pumpTree(tester);

    final elements =
        TxlemetryMaskController.instance.getMaskElements(includeAllWidgets: true);

    expect(elements, isNotNull);
    expect(types(elements!), isNot(contains('Text')));
    expect(types(elements), isNot(contains('RichText')));
    expect(types(elements), contains('RawImage'));
  });

  testWidgets('records sensitivity on widget-level mask data', (tester) async {
    await setupTxlemetry(maskAllTexts: false, maskAllImages: false);
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: TxlemetryMaskController.instance.containerKey,
        child: const Scaffold(
            body: Column(children: [
          TxlemetryUnmaskWidget(
              child: Column(children: [
            TextField(obscureText: true),
            CupertinoTextField(autofillHints: [AutofillHints.oneTimeCode]),
          ])),
          TxlemetryMaskWidget(child: Text('explicit mask')),
        ])),
      ),
    ));
    final elements = TxlemetryMaskController.instance
        .getMaskElements(includeAllWidgets: false)!;
    final inputs = elements.where((e) =>
        e.widget is TextField ||
        e.widget is CupertinoTextField ||
        e.widget is EditableText);
    expect(inputs.map((e) => e.widget.runtimeType).toSet(),
        containsAll([TextField, CupertinoTextField, EditableText]));
    expect(inputs.every((e) => e.isSensitiveText), isTrue);
    expect(elements.where((e) => e.widget is TxlemetryMaskWidget), isNotEmpty);
    expect(
        elements
            .where((e) => e.widget is TxlemetryMaskWidget)
            .every((e) => !e.isSensitiveText),
        isTrue);
  });

  testWidgets('maskAllTexts=true still masks Text', (tester) async {
    await setupTxlemetry(maskAllTexts: true, maskAllImages: true);
    await pumpTree(tester);

    final elements =
        TxlemetryMaskController.instance.getMaskElements(includeAllWidgets: true);

    expect(elements, isNotNull);
    expect(types(elements!), contains('Text'));
  });
}
