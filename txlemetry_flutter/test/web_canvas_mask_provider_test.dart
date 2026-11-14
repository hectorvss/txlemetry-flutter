@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/replay/web/web_canvas_mask_provider.dart';
import 'package:web/web.dart' as web;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  JSObject? capturedConfig;
  var setConfigCalls = 0;
  var stopRecordingCalls = 0;
  var startRecordingCalls = 0;

  JSObject installTxlemetryStub({
    JSObject? sessionRecording,
    bool withConfig = true,
    bool loaded = true,
    bool recordingStarted = false,
    bool declaresMaskProvider = true,
    String? version,
  }) {
    capturedConfig = null;
    setConfigCalls = 0;
    stopRecordingCalls = 0;
    startRecordingCalls = 0;
    final stub = JSObject();
    if (withConfig) {
      final config = JSObject();
      if (declaresMaskProvider) {
        sessionRecording ??= JSObject();
        final existing =
            sessionRecording.getProperty<JSAny?>('canvasCapture'.toJS);
        final canvasCapture =
            existing.isA<JSObject>() ? existing as JSObject : JSObject();
        canvasCapture.setProperty('maskRegionsFn'.toJS, null);
        sessionRecording.setProperty('canvasCapture'.toJS, canvasCapture);
      }
      if (sessionRecording != null) {
        config.setProperty('session_recording'.toJS, sessionRecording);
      }
      stub.setProperty('config'.toJS, config);
      // the real instance carries __loaded; the snippet stub (withConfig:
      // false) has neither config nor __loaded
      stub.setProperty('__loaded'.toJS, loaded.toJS);
    }
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        capturedConfig = cfg;
        setConfigCalls++;
      }).toJS,
    );
    var recordingState = recordingStarted;
    stub.setProperty(
      'sessionRecordingStarted'.toJS,
      (() => recordingState.toJS).toJS,
    );
    stub.setProperty(
      'stopSessionRecording'.toJS,
      (() {
        stopRecordingCalls++;
        recordingState = false;
      }).toJS,
    );
    stub.setProperty(
      'startSessionRecording'.toJS,
      (() {
        startRecordingCalls++;
        recordingState = true;
      }).toJS,
    );
    if (version != null) {
      stub.setProperty('version'.toJS, version.toJS);
    }
    web.window.setProperty('txlemetry'.toJS, stub);
    return stub;
  }

  int Function() interceptWarns() {
    final consoleObject = web.window.getProperty<JSObject>('console'.toJS);
    final originalWarn = consoleObject.getProperty<JSAny?>('warn'.toJS);
    var warnCalls = 0;
    consoleObject.setProperty(
      'warn'.toJS,
      ((JSAny? message) {
        warnCalls++;
      }).toJS,
    );
    addTearDown(() => consoleObject.setProperty('warn'.toJS, originalWarn));
    return () => warnCalls;
  }

  // cancel the previous test's retry chain so a stale chain cannot apply
  // config against this test's stub
  setUp(WebCanvasMaskProvider.resetForTesting);

  tearDown(() {
    WebCanvasMaskProvider.resetForTesting();
    web.window.setProperty('txlemetry'.toJS, null);
  });

  JSObject capturedSessionRecording() {
    expect(capturedConfig, isNotNull);
    final sessionRecording =
        capturedConfig!.getProperty<JSAny?>('session_recording'.toJS);
    expect(sessionRecording.isA<JSObject>(), isTrue);
    return sessionRecording as JSObject;
  }

  for (final unsized in [false, true]) {
    testWidgets('custom-paint regions fail closed for unsized=$unsized',
        (tester) async {
      installTxlemetryStub();
      final config = TxlemetryConfig('phc_test');
      config.sessionReplayConfig
        ..maskAllTexts = false
        ..maskAllImages = false
        ..maskCustomPaint = true;
      WebCanvasMaskProvider(config).register();

      await tester.pumpWidget(
        TxlemetryWidget(
          child: Align(
            alignment: Alignment.topLeft,
            child: CustomPaint(
              size: unsized ? Size.zero : const Size(100, 40),
              painter: BannerPainter(
                message: 'sensitive',
                layoutDirection: TextDirection.ltr,
                textDirection: TextDirection.ltr,
                location: BannerLocation.topStart,
              ),
            ),
          ),
        ),
      );

      final flutterView = web.document.createElement('flutter-view');
      final canvas = web.document.createElement('canvas');
      flutterView.appendChild(canvas);
      web.document.body!.appendChild(flutterView);
      WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
      try {
        final regionsFn = capturedSessionRecording()
            .getProperty<JSObject>('canvasCapture'.toJS)
            .getProperty<JSFunction>('maskRegionsFn'.toJS);
        final result = regionsFn.callAsFunction(null, canvas);
        if (unsized) {
          expect(result, isNull);
          return;
        }
        final regions = result as JSArray<JSObject>;
        expect(regions.toDart, isNotEmpty);
        expect(
          regions.toDart.any((region) =>
              region.getProperty<JSNumber>('width'.toJS).toDartDouble >= 100 &&
              region.getProperty<JSNumber>('height'.toJS).toDartDouble >= 40),
          isTrue,
        );
      } finally {
        flutterView.remove();
      }
    });
  }

  test('warns when only custom-paint masking is requested without a provider',
      () {
    final captureCanvas = JSObject()
      ..setProperty('recordCanvas'.toJS, true.toJS);
    final sessionRecording = JSObject()
      ..setProperty('captureCanvas'.toJS, captureCanvas);
    installTxlemetryStub(
      declaresMaskProvider: false,
      sessionRecording: sessionRecording,
    );
    final warns = interceptWarns();
    final config = TxlemetryConfig('phc_test');
    config.sessionReplayConfig
      ..maskAllTexts = false
      ..maskAllImages = false
      ..maskCustomPaint = true;

    WebCanvasMaskProvider(config).register();

    expect(warns(), 1);
  });

  test('leaves txlemetry-js untouched when the app declares no mask provider',
      () {
    installTxlemetryStub(declaresMaskProvider: true, recordingStarted: true);
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(capturedConfig, isNull);
    expect(stopRecordingCalls, 0);
    expect(startRecordingCalls, 0);
  });

  testWidgets('an unmask widget mounted before register opts in',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    await tester
        .pumpWidget(const TxlemetryUnmaskWidget(child: SizedBox.shrink()));
    expect(setConfigCalls, 0);
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets('an unmask widget alone enables safe canvas regions',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(capturedConfig, isNull);
    await tester.pumpWidget(const TxlemetryWidget(
        child: MaterialApp(
      home: Scaffold(
          body: Column(children: [
        Text('private sibling'),
        TxlemetryUnmaskWidget(
            child: Column(children: [
          Text('safe label'),
          TextField(obscureText: true),
          TextField(autofillHints: [AutofillHints.creditCardNumber]),
        ])),
      ])),
    )));
    final recording = capturedSessionRecording();
    expect(recording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
        'flt-semantics-host');
    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
    final flutterView = web.document.createElement('flutter-view');
    flutterView.setAttribute('style', 'position: fixed; left: 0; top: 0');
    final canvas = web.document.createElement('canvas');
    canvas.setAttribute('style', 'position: absolute; left: 0; top: 0');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
    try {
      final regionsFn = recording
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      final regions =
          (regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>)
              .toDart
              .map((region) => Rect.fromLTWH(
                    region.getProperty<JSNumber>('x'.toJS).toDartDouble,
                    region.getProperty<JSNumber>('y'.toJS).toDartDouble,
                    region.getProperty<JSNumber>('width'.toJS).toDartDouble,
                    region.getProperty<JSNumber>('height'.toJS).toDartDouble,
                  ))
              .toList();
      expect(
          regions.any(
              (r) => r.contains(tester.getCenter(find.text('safe label')))),
          isFalse);
      expect(
          regions.any((r) =>
              r.contains(tester.getCenter(find.text('private sibling')))),
          isTrue);
      for (final field in find.byType(EditableText).evaluate()) {
        expect(
            regions.any((r) =>
                r.contains(tester.getCenter(find.byWidget(field.widget)))),
            isTrue);
      }
    } finally {
      flutterView.remove();
    }
  });

  testWidgets('unmask and mask mounts share a single registration',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    await tester
        .pumpWidget(const TxlemetryUnmaskWidget(child: SizedBox.shrink()));
    expect(setConfigCalls, 1);
    await tester.pumpWidget(const TxlemetryMaskWidget(child: SizedBox.shrink()));
    await tester
        .pumpWidget(const TxlemetryUnmaskWidget(child: SizedBox.shrink()));
    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets('an unmask widget outside the tracked tree does not opt in',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Expanded(child: TxlemetryWidget(child: Container())),
        const TxlemetryUnmaskWidget(child: SizedBox.shrink()),
      ]),
    ));
    expect(setConfigCalls, 0);
    expect(stopRecordingCalls, 0);
    expect(startRecordingCalls, 0);
  });

  testWidgets(
      'unmounting an unmask widget outside the tracked tree recovers frames',
      (tester) async {
    installTxlemetryStub(recordingStarted: true);
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    Widget layout(bool outside) => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            Expanded(child: TxlemetryWidget(child: Container())),
            if (outside) const TxlemetryUnmaskWidget(child: SizedBox.shrink()),
          ]),
        );
    await tester.pumpWidget(layout(true));
    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
    try {
      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      expect(regionsFn.callAsFunction(null, canvas), isNull);
      await tester.pumpWidget(layout(false));
      expect(regionsFn.callAsFunction(null, canvas), isNotNull);
    } finally {
      flutterView.remove();
    }
  });

  testWidgets('opts in when a TxlemetryMaskWidget mounted before register()',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);

    await tester.pumpWidget(const TxlemetryMaskWidget(child: SizedBox.shrink()));
    expect(setConfigCalls, 0);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets('a mounted TxlemetryMaskWidget opts the app in on its own',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(capturedConfig, isNull);

    await tester.pumpWidget(const TxlemetryMaskWidget(child: SizedBox.shrink()));

    final sessionRecording = capturedSessionRecording();
    expect(
      sessionRecording
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSAny?>('maskRegionsFn'.toJS)
          .isA<JSFunction>(),
      isTrue,
    );
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      'flt-semantics-host',
    );
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets('registers once however many TxlemetryMaskWidgets mount',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    Widget maskWidgets(int count) => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: List.generate(
              count,
              (_) => const TxlemetryMaskWidget(child: SizedBox.shrink()),
            ),
          ),
        );
    await tester.pumpWidget(maskWidgets(3));
    await tester.pumpWidget(maskWidgets(5));

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets(
      'a TxlemetryMaskWidget mount is a no-op when txlemetry.init already '
      'opted in', (tester) async {
    installTxlemetryStub(recordingStarted: true);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(setConfigCalls, 1);

    await tester.pumpWidget(const TxlemetryMaskWidget(child: SizedBox.shrink()));

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets(
      'an exception during the mount-triggered apply does not consume the '
      'opt-in', (tester) async {
    final stub = installTxlemetryStub(declaresMaskProvider: false);
    var calls = 0;
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        calls++;
        if (calls == 1) {
          throw StateError('stub failure');
        }
        capturedConfig = cfg;
      }).toJS,
    );

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    await tester.pumpWidget(const TxlemetryMaskWidget(child: SizedBox.shrink()));
    expect(capturedConfig, isNull);

    await tester.pump(const Duration(milliseconds: 600));

    expect(calls, 2);
    expect(capturedConfig, isNotNull);
  });

  testWidgets('opts in once txlemetry-js arrives after the widget mounted',
      (tester) async {
    web.window.setProperty('txlemetry'.toJS, null);
    capturedConfig = null;

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    await tester.pumpWidget(const TxlemetryMaskWidget(child: SizedBox.shrink()));
    expect(capturedConfig, isNull);

    installTxlemetryStub(declaresMaskProvider: false);
    await tester.pump(const Duration(milliseconds: 300));

    expect(setConfigCalls, 1);
  });

  testWidgets(
      'a retry chain from a throw-path apply cannot outlive a second '
      'register()', (tester) async {
    final stub = installTxlemetryStub(recordingStarted: true);
    var successfulSetConfigs = 0;
    var failing = true;
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        if (failing) {
          throw StateError('stub failure');
        }
        successfulSetConfigs++;
        capturedConfig = cfg;
      }).toJS,
    );

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    // the first apply threw, so a retry is pending; a mask widget mounting
    // now must join that chain instead of starting a second one
    await tester.pumpWidget(const TxlemetryMaskWidget(child: SizedBox.shrink()));
    expect(successfulSetConfigs, 0);

    failing = false;
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(successfulSetConfigs, 1);

    // an orphaned first-chain timer would fire here and apply a second time
    await tester.pump(const Duration(seconds: 5));

    expect(successfulSetConfigs, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets(
      'a mask widget outside the tracked TxlemetryWidget tree does not opt in',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Expanded(child: TxlemetryWidget(child: Container())),
            const TxlemetryMaskWidget(child: SizedBox.shrink()),
          ],
        ),
      ),
    );

    expect(setConfigCalls, 0);
    expect(stopRecordingCalls, 0);
    expect(startRecordingCalls, 0);
  });

  testWidgets(
      'a mask widget that mounts before any TxlemetryWidget opts in '
      '(no-TxlemetryWidget shape), but a later TxlemetryWidget that excludes it '
      'makes frames fail closed', (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    Widget layout({required bool withTxlemetryWidget}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              if (withTxlemetryWidget)
                Expanded(child: TxlemetryWidget(child: Container())),
              const TxlemetryMaskWidget(child: SizedBox.shrink()),
            ],
          ),
        );

    await tester.pumpWidget(layout(withTxlemetryWidget: false));
    expect(setConfigCalls, 1);

    await tester.pumpWidget(layout(withTxlemetryWidget: true));

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);

    // the latched opt-in must not ship the sibling tree's rects while this
    // mask widget sits outside it
    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
    try {
      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      expect(regionsFn.callAsFunction(null, canvas), isNull);
    } finally {
      flutterView.remove();
    }
  });

  testWidgets(
      'a mask widget that mounts before a TxlemetryWidget that later contains '
      'it keeps producing regions', (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;
    WebCanvasMaskProvider(config).register();

    final maskKey = GlobalKey();
    Widget mask() => Align(
          alignment: Alignment.topLeft,
          child: TxlemetryMaskWidget(
            key: maskKey,
            child: const SizedBox(width: 30, height: 40),
          ),
        );

    await tester.pumpWidget(mask());
    expect(setConfigCalls, 1);

    await tester.pumpWidget(TxlemetryWidget(child: mask()));

    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
    try {
      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      final regions =
          regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>;

      expect(regions.toDart, hasLength(1));
      final region = regions.toDart.first;
      expect(
        region.getProperty<JSNumber>('width'.toJS).toDartDouble,
        greaterThanOrEqualTo(30),
      );
      expect(
        region.getProperty<JSNumber>('height'.toJS).toDartDouble,
        greaterThanOrEqualTo(40),
      );
    } finally {
      flutterView.remove();
    }
  });

  testWidgets(
      'frames recover once the mask widget outside the tracked tree is '
      'removed', (tester) async {
    installTxlemetryStub(recordingStarted: true);
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;
    WebCanvasMaskProvider(config).register();

    Widget layout({required bool withOutsideMask}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Expanded(child: TxlemetryWidget(child: Container())),
              if (withOutsideMask)
                const TxlemetryMaskWidget(child: SizedBox.shrink()),
            ],
          ),
        );

    await tester.pumpWidget(layout(withOutsideMask: true));

    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
    try {
      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      expect(regionsFn.callAsFunction(null, canvas), isNull);

      await tester.pumpWidget(layout(withOutsideMask: false));

      expect(regionsFn.callAsFunction(null, canvas), isNotNull);
    } finally {
      flutterView.remove();
    }
  });

  testWidgets('a mask widget inside the tracked TxlemetryWidget tree opts in',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    await tester.pumpWidget(
      TxlemetryWidget(child: TxlemetryMaskWidget(child: const SizedBox.shrink())),
    );

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets(
      'a mask widget in a dialog above TxlemetryWidget opts in and produces '
      'regions', (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, recordingStarted: true);
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;
    WebCanvasMaskProvider(config).register();
    expect(setConfigCalls, 0);

    // TxlemetryWidget sits UNDER the home route, so the walk roots at the root
    // navigator and covers the dialog — the tracked-tree boundary must too
    await tester.pumpWidget(
      MaterialApp(
        home: TxlemetryWidget(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => Align(
                    alignment: Alignment.topLeft,
                    child: TxlemetryMaskWidget(
                      child: const SizedBox(width: 30, height: 40),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    expect(setConfigCalls, 0);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(setConfigCalls, 1);

    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
    try {
      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      final regions = regionsFn.callAsFunction(null, canvas);
      expect(regions, isNotNull);
      expect((regions as JSArray<JSObject>).toDart, isNotEmpty);
    } finally {
      flutterView.remove();
    }
  });

  test('registers the mask provider via set_config', () {
    installTxlemetryStub();

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    final sessionRecording = capturedSessionRecording();
    final canvasCapture =
        sessionRecording.getProperty<JSObject>('canvasCapture'.toJS);
    expect(
      canvasCapture.getProperty<JSAny?>('maskRegionsFn'.toJS).isA<JSFunction>(),
      isTrue,
    );
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      'flt-semantics-host',
    );
  });

  test('preserves existing session_recording config when merging', () {
    final existingCanvasCapture = JSObject()
      ..setProperty('resolutionScale'.toJS, 0.5.toJS);
    final existingCaptureCanvas = JSObject()
      ..setProperty('recordCanvas'.toJS, true.toJS)
      ..setProperty('canvasFps'.toJS, 2.toJS);
    final existingSessionRecording = JSObject()
      ..setProperty('blockSelector'.toJS, '.secret'.toJS)
      ..setProperty('maskAllInputs'.toJS, false.toJS)
      ..setProperty('canvasCapture'.toJS, existingCanvasCapture)
      ..setProperty('captureCanvas'.toJS, existingCaptureCanvas);
    installTxlemetryStub(sessionRecording: existingSessionRecording);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    final sessionRecording = capturedSessionRecording();
    expect(
      sessionRecording.getProperty<JSAny?>('maskAllInputs'.toJS).dartify(),
      false,
    );
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      '.secret, flt-semantics-host',
    );
    final canvasCapture =
        sessionRecording.getProperty<JSObject>('canvasCapture'.toJS);
    expect(
      canvasCapture.getProperty<JSAny?>('resolutionScale'.toJS).dartify(),
      0.5,
    );
    expect(
      canvasCapture.getProperty<JSAny?>('maskRegionsFn'.toJS).isA<JSFunction>(),
      isTrue,
    );
    final captureCanvas =
        sessionRecording.getProperty<JSObject>('captureCanvas'.toJS);
    expect(
      captureCanvas.getProperty<JSAny?>('recordCanvas'.toJS).dartify(),
      true,
    );
    expect(
      captureCanvas.getProperty<JSAny?>('canvasFps'.toJS).dartify(),
      2,
    );
    expect(
      captureCanvas.getProperty<JSAny?>('maskRegionsFn'.toJS),
      isNull,
    );
  });

  test(
      'appends the semantics selector when an existing one only contains it '
      'as a substring', () {
    final existingSessionRecording = JSObject()
      ..setProperty('blockSelector'.toJS, '.not-flt-semantics-host'.toJS);
    installTxlemetryStub(sessionRecording: existingSessionRecording);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(
      capturedSessionRecording()
          .getProperty<JSAny?>('blockSelector'.toJS)
          .dartify(),
      '.not-flt-semantics-host, flt-semantics-host',
    );
  });

  test('blocks the semantics host even when maskAllTexts is false', () {
    installTxlemetryStub();
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false;

    WebCanvasMaskProvider(config).register();

    final sessionRecording = capturedSessionRecording();
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      'flt-semantics-host',
    );
  });

  test('returns no regions for a canvas outside the flutter view', () {
    installTxlemetryStub();
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    final regionsFn = capturedSessionRecording()
        .getProperty<JSObject>('canvasCapture'.toJS)
        .getProperty<JSFunction>('maskRegionsFn'.toJS);
    final canvas = web.document.createElement('canvas');
    final regions = regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>;

    expect(regions.toDart, isEmpty);
  });

  group('app-provided maskRegionsFn delegation', () {
    JSObject sessionRecordingWithAppFn(JSFunction appFn) {
      final canvasCapture = JSObject()
        ..setProperty('maskRegionsFn'.toJS, appFn);
      return JSObject()..setProperty('canvasCapture'.toJS, canvasCapture);
    }

    JSFunction installedRegionsFn() => capturedSessionRecording()
        .getProperty<JSObject>('canvasCapture'.toJS)
        .getProperty<JSFunction>('maskRegionsFn'.toJS);

    test('a canvas outside every flutter view gets the app callback answer',
        () {
      var appFnCalls = 0;
      final appFn = ((web.HTMLCanvasElement c) {
        appFnCalls++;
        return [JSObject()..setProperty('x'.toJS, 42.toJS)].toJS;
      }).toJS;
      installTxlemetryStub(
        declaresMaskProvider: false,
        sessionRecording: sessionRecordingWithAppFn(appFn),
      );
      WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

      final canvas = web.document.createElement('canvas');
      final result = installedRegionsFn().callAsFunction(null, canvas);

      expect(appFnCalls, 1);
      final regions = (result as JSArray<JSObject>).toDart;
      expect(regions, hasLength(1));
      expect(regions.single.getProperty<JSNumber>('x'.toJS).toDartInt, 42);
    });

    test('an app callback answering null keeps its fail-closed meaning', () {
      JSAny? nullAppFn(web.HTMLCanvasElement c) => null;
      final appFn = nullAppFn.toJS;
      installTxlemetryStub(
        declaresMaskProvider: false,
        sessionRecording: sessionRecordingWithAppFn(appFn),
      );
      WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

      final canvas = web.document.createElement('canvas');
      expect(installedRegionsFn().callAsFunction(null, canvas), isNull);
    });

    test('a throwing app callback fails closed', () {
      JSAny? throwingAppFn(web.HTMLCanvasElement c) {
        throw StateError('app fn exploded');
      }

      final appFn = throwingAppFn.toJS;
      installTxlemetryStub(
        declaresMaskProvider: false,
        sessionRecording: sessionRecordingWithAppFn(appFn),
      );
      WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

      final canvas = web.document.createElement('canvas');
      expect(installedRegionsFn().callAsFunction(null, canvas), isNull);
    });

    test(
        'a second setup does not mistake the installed callback for the app '
        'fn', () {
      var appFnCalls = 0;
      final appFn = ((web.HTMLCanvasElement c) {
        appFnCalls++;
        return JSArray<JSObject>();
      }).toJS;
      installTxlemetryStub(
        declaresMaskProvider: false,
        sessionRecording: sessionRecordingWithAppFn(appFn),
      );
      WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

      // txlemetry-js merges set_config into its live config, so a second
      // setup()'s apply reads back the provider's own installed callback
      final firstApply = capturedSessionRecording();
      installTxlemetryStub(
        declaresMaskProvider: false,
        sessionRecording: firstApply,
      );
      WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

      final canvas = web.document.createElement('canvas');
      installedRegionsFn().callAsFunction(null, canvas);

      expect(appFnCalls, 1);
    });
  });

  test(
      'fails closed for a flutter-view canvas when no TxlemetryWidget is '
      'mounted', () {
    installTxlemetryStub();
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    final regionsFn = capturedSessionRecording()
        .getProperty<JSObject>('canvasCapture'.toJS)
        .getProperty<JSFunction>('maskRegionsFn'.toJS);
    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
    try {
      expect(regionsFn.callAsFunction(null, canvas), isNull);
    } finally {
      flutterView.remove();
    }
  });

  test('warns once when the widget-tree walk keeps failing', () {
    installTxlemetryStub();
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    final consoleObject = web.window.getProperty<JSObject>('console'.toJS);
    final originalWarn = consoleObject.getProperty<JSAny?>('warn'.toJS);
    var warnCalls = 0;
    consoleObject.setProperty(
      'warn'.toJS,
      ((JSAny? message) {
        warnCalls++;
      }).toJS,
    );

    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
    try {
      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      for (var i = 0; i < 12; i++) {
        expect(regionsFn.callAsFunction(null, canvas), isNull);
      }
      expect(warnCalls, 1);
    } finally {
      flutterView.remove();
      consoleObject.setProperty('warn'.toJS, originalWarn);
    }
  });

  testWidgets(
      'canvas unmask regions override explicit masks but keep sensitive inputs',
      (tester) async {
    await tester.pumpWidget(const TxlemetryWidget(
      child: MaterialApp(
          home: Scaffold(
              body: TxlemetryMaskWidget(
                  child: Column(children: [
        Text('private sibling'),
        TxlemetryUnmaskWidget(
            child: Column(children: [
          Text('safe label'),
          TextField(autofillHints: [AutofillHints.creditCardNumber]),
          TextField(autofillHints: [AutofillHints.email]),
          TxlemetryMaskWidget(child: Text('nested explicit mask')),
        ])),
      ])))),
    ));
    final flutterView = web.document.createElement('flutter-view');
    flutterView.setAttribute('style', 'position: fixed; left: 0; top: 0');
    final canvas = web.document.createElement('canvas');
    canvas.setAttribute('style', 'position: absolute; left: 0; top: 0');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    installTxlemetryStub();
    try {
      WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
      WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      final regions =
          (regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>)
              .toDart
              .map((region) => Rect.fromLTWH(
                    region.getProperty<JSNumber>('x'.toJS).toDartDouble,
                    region.getProperty<JSNumber>('y'.toJS).toDartDouble,
                    region.getProperty<JSNumber>('width'.toJS).toDartDouble,
                    region.getProperty<JSNumber>('height'.toJS).toDartDouble,
                  ))
              .toList();
      expect(
          regions.any((rect) =>
              rect.contains(tester.getCenter(find.text('safe label')))),
          isFalse);
      expect(
          regions.any((rect) => rect
              .contains(tester.getCenter(find.text('nested explicit mask')))),
          isFalse);
      for (final finder in [
        find.text('private sibling'),
        ...find
            .byType(EditableText)
            .evaluate()
            .map((e) => find.byWidget(e.widget)),
      ]) {
        expect(regions.any((rect) => rect.contains(tester.getCenter(finder))),
            isTrue);
      }
    } finally {
      flutterView.remove();
    }
  });

  testWidgets('maps mask rects into canvas-relative coordinates',
      (tester) async {
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;

    await tester.pumpWidget(
      TxlemetryWidget(
        child: Padding(
          padding: const EdgeInsets.only(left: 100, top: 200),
          child: Align(
            alignment: Alignment.topLeft,
            child: TxlemetryMaskWidget(
              child: const SizedBox(width: 30, height: 40),
            ),
          ),
        ),
      ),
    );

    final flutterView = web.document.createElement('flutter-view');
    flutterView.setAttribute('style', 'position: fixed; left: 50px; top: 60px');
    final canvas = web.document.createElement('canvas');
    canvas.setAttribute('style', 'position: absolute; left: 20px; top: 30px');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);

    installTxlemetryStub();
    try {
      // the harness's own flutter-view plus this fake one make the real
      // <body> host ambiguous, which now fails closed
      WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
      WebCanvasMaskProvider(config).register();

      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      final regions =
          regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>;

      expect(regions.toDart, hasLength(1));
      final region = regions.toDart.first;
      expect(region.getProperty<JSNumber>('x'.toJS).toDartDouble, 79);
      expect(region.getProperty<JSNumber>('y'.toJS).toDartDouble, 169);
      expect(region.getProperty<JSNumber>('width'.toJS).toDartDouble, 32);
      expect(region.getProperty<JSNumber>('height'.toJS).toDartDouble, 42);
    } finally {
      flutterView.remove();
    }
  });

  testWidgets('scales mask rects by an ancestor transform around the container',
      (tester) async {
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;

    await tester.pumpWidget(
      Transform.scale(
        scale: 2,
        alignment: Alignment.topLeft,
        child: TxlemetryWidget(
          child: Align(
            alignment: Alignment.topLeft,
            child: TxlemetryMaskWidget(
              child: const SizedBox(width: 30, height: 40),
            ),
          ),
        ),
      ),
    );

    final flutterView = web.document.createElement('flutter-view');
    flutterView.setAttribute('style', 'position: fixed; left: 0; top: 0');
    final canvas = web.document.createElement('canvas');
    canvas.setAttribute('style', 'position: absolute; left: 0; top: 0');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);

    installTxlemetryStub();
    try {
      WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
      WebCanvasMaskProvider(config).register();

      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      final regions =
          regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>;

      // container-local (0,0,30,40) outsets to (-1,-1,32,42), then doubles
      expect(regions.toDart, hasLength(1));
      final region = regions.toDart.first;
      expect(region.getProperty<JSNumber>('x'.toJS).toDartDouble, -2);
      expect(region.getProperty<JSNumber>('y'.toJS).toDartDouble, -2);
      expect(region.getProperty<JSNumber>('width'.toJS).toDartDouble, 64);
      expect(region.getProperty<JSNumber>('height'.toJS).toDartDouble, 84);
    } finally {
      flutterView.remove();
    }
  });

  testWidgets('fails closed when an ancestor transform is singular',
      (tester) async {
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;

    await tester.pumpWidget(
      Transform(
        transform: Matrix4.identity()..setEntry(3, 3, 0),
        child: TxlemetryWidget(
          child: Align(
            alignment: Alignment.topLeft,
            child: TxlemetryMaskWidget(
              child: const SizedBox(width: 30, height: 40),
            ),
          ),
        ),
      ),
    );

    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);

    installTxlemetryStub();
    try {
      WebCanvasMaskProvider.debugOwnViewHostOverride = flutterView;
      WebCanvasMaskProvider(config).register();

      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);

      expect(regionsFn.callAsFunction(null, canvas), isNull);
    } finally {
      flutterView.remove();
    }
  });

  testWidgets(
      'fails closed for a canvas in a foreign flutter-view on a multi-view '
      'page', (tester) async {
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;

    await tester.pumpWidget(
      TxlemetryWidget(
        child: Align(
          alignment: Alignment.topLeft,
          child: TxlemetryMaskWidget(
            child: const SizedBox(width: 30, height: 40),
          ),
        ),
      ),
    );

    web.Element embeddedView(web.Element host) {
      final view = web.document.createElement('flutter-view');
      final canvas = web.document.createElement('canvas');
      view.appendChild(canvas);
      host.appendChild(view);
      return canvas;
    }

    final ownHost = web.document.createElement('div');
    final ownCanvas = embeddedView(ownHost);
    final foreignHost = web.document.createElement('div');
    final foreignCanvas = embeddedView(foreignHost);
    web.document.body!.appendChild(ownHost);
    web.document.body!.appendChild(foreignHost);

    installTxlemetryStub();
    try {
      WebCanvasMaskProvider.debugOwnViewHostOverride = ownHost;
      WebCanvasMaskProvider(config).register();

      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);

      expect(regionsFn.callAsFunction(null, foreignCanvas), isNull);
      final regions =
          regionsFn.callAsFunction(null, ownCanvas) as JSArray<JSObject>;
      expect(regions.toDart, hasLength(1));
    } finally {
      ownHost.remove();
      foreignHost.remove();
    }
  });

  testWidgets(
      'fails closed for every canvas when the host contains more than one '
      'flutter-view', (tester) async {
    final config = TxlemetryConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;

    await tester.pumpWidget(
      TxlemetryWidget(
        child: Align(
          alignment: Alignment.topLeft,
          child: TxlemetryMaskWidget(
            child: const SizedBox(width: 30, height: 40),
          ),
        ),
      ),
    );

    web.Element embeddedView(web.Element host) {
      final view = web.document.createElement('flutter-view');
      final canvas = web.document.createElement('canvas');
      view.appendChild(canvas);
      host.appendChild(view);
      return canvas;
    }

    // full-page mode: getHostElement resolves to <body>, which hosts both
    // our view and the foreign one
    final sharedHost = web.document.createElement('div');
    final ownCanvas = embeddedView(sharedHost);
    final foreignCanvas = embeddedView(sharedHost);
    web.document.body!.appendChild(sharedHost);

    installTxlemetryStub();
    try {
      WebCanvasMaskProvider.debugOwnViewHostOverride = sharedHost;
      WebCanvasMaskProvider(config).register();

      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);

      expect(regionsFn.callAsFunction(null, ownCanvas), isNull);
      expect(regionsFn.callAsFunction(null, foreignCanvas), isNull);
    } finally {
      sharedHost.remove();
    }
  });

  test('defers set_config until txlemetry-js exposes its config', () {
    installTxlemetryStub(withConfig: false);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(capturedConfig, isNull);
  });

  testWidgets(
      'applies config after txlemetry-js appears with no snippet stub at all',
      (tester) async {
    web.window.setProperty('txlemetry'.toJS, null);
    capturedConfig = null;

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(capturedConfig, isNull);

    installTxlemetryStub();
    await tester.pump(const Duration(milliseconds: 249));
    expect(capturedConfig, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(capturedConfig, isNotNull);
  });

  testWidgets(
      'applies config after array.js replaces the snippet stub with the real '
      'instance', (tester) async {
    installTxlemetryStub(withConfig: false);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(capturedConfig, isNull);

    installTxlemetryStub();
    await tester.pump(const Duration(milliseconds: 250));
    expect(capturedConfig, isNotNull);
  });

  testWidgets(
      'keeps retrying while txlemetry is present but uninitialized, then '
      'applies once init declares the mask provider', (tester) async {
    final stub = installTxlemetryStub(loaded: false, declaresMaskProvider: false);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    await tester.pump(const Duration(milliseconds: 250));
    // present-but-uninitialized must not be classified as not-opted-in
    expect(capturedConfig, isNull);

    final canvasCapture = JSObject()..setProperty('maskRegionsFn'.toJS, null);
    final sessionRecording = JSObject()
      ..setProperty('canvasCapture'.toJS, canvasCapture);
    stub
        .getProperty<JSObject>('config'.toJS)
        .setProperty('session_recording'.toJS, sessionRecording);
    stub.setProperty('__loaded'.toJS, true.toJS);

    await tester.pump(const Duration(milliseconds: 500));
    expect(capturedConfig, isNotNull);
  });

  testWidgets('an exception during one retry tick does not kill the chain',
      (tester) async {
    web.window.setProperty('txlemetry'.toJS, null);
    capturedConfig = null;

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    final stub = installTxlemetryStub();
    var setConfigCalls = 0;
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        setConfigCalls++;
        if (setConfigCalls == 1) {
          throw StateError('stub failure');
        }
        capturedConfig = cfg;
      }).toJS,
    );

    await tester.pump(const Duration(milliseconds: 250));
    expect(setConfigCalls, 1);
    expect(capturedConfig, isNull);
    await tester.pump(const Duration(milliseconds: 500));
    expect(setConfigCalls, 2);
    expect(capturedConfig, isNotNull);
  });

  testWidgets("a second register cancels the predecessor's retry chain",
      (tester) async {
    web.window.setProperty('txlemetry'.toJS, null);
    capturedConfig = null;

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    final stub = installTxlemetryStub(recordingStarted: true);
    var setConfigCalls = 0;
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        setConfigCalls++;
        capturedConfig = cfg;
      }).toJS,
    );

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(seconds: 4));
    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(capturedConfig, isNotNull);
  });

  testWidgets(
      'retries the full apply when the restart throws on first register',
      (tester) async {
    final stub = installTxlemetryStub(recordingStarted: true);
    var stopAttempts = 0;
    stub.setProperty(
      'stopSessionRecording'.toJS,
      (() {
        stopAttempts++;
        if (stopAttempts == 1) {
          throw StateError('stub stop failure');
        }
      }).toJS,
    );

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(startRecordingCalls, 0);

    await tester.pump(const Duration(milliseconds: 250));

    expect(stopAttempts, 2);
    expect(startRecordingCalls, 1);
    expect(capturedConfig, isNotNull);
  });

  testWidgets('backs off when the apply keeps throwing', (tester) async {
    final stub = installTxlemetryStub();
    var attempts = 0;
    void failingSetConfig(JSObject cfg) {
      attempts++;
      throw StateError('stub failure');
    }

    stub.setProperty('set_config'.toJS, failingSetConfig.toJS);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(attempts, 1);
    var expected = 1;
    for (final delay in [250, 500, 1000, 2000, 4000, 4000]) {
      await tester.pump(Duration(milliseconds: delay - 1));
      expect(attempts, expected);
      await tester.pump(const Duration(milliseconds: 1));
      expect(attempts, ++expected);
    }
    WebCanvasMaskProvider.resetForTesting();
  });

  testWidgets('finishes the restart when stop succeeds but start throws',
      (tester) async {
    final stub = installTxlemetryStub(recordingStarted: true);
    var startAttempts = 0;
    stub.setProperty(
      'startSessionRecording'.toJS,
      (() {
        startAttempts++;
        if (startAttempts == 1) {
          throw StateError('stub start failure');
        }
      }).toJS,
    );

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    // the stub now reports the recording as stopped, so the retry must not
    // skip the restart block
    expect(stopRecordingCalls, 1);
    expect(startAttempts, 1);

    await tester.pump(const Duration(milliseconds: 250));

    expect(startAttempts, 2);
    expect(stopRecordingCalls, 1);
    expect(capturedConfig, isNotNull);
  });

  test('restarts an in-flight recording so the new config applies', () {
    installTxlemetryStub(recordingStarted: true);

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  test('does not restart recording when none is in flight', () {
    installTxlemetryStub();

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(stopRecordingCalls, 0);
    expect(startRecordingCalls, 0);
  });

  test('warns once but still registers when txlemetry-js is too old', () {
    installTxlemetryStub(version: '1.399.2');
    WebCanvasMaskProvider.debugMinTxlemetryJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(warns(), 1);
    expect(capturedConfig, isNotNull);
  });

  test('does not warn when txlemetry-js meets the minimum', () {
    installTxlemetryStub(version: '1.407.0');
    WebCanvasMaskProvider.debugMinTxlemetryJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(warns(), 0);
    expect(capturedConfig, isNotNull);
  });

  test('does not warn when txlemetry-js exposes no version', () {
    installTxlemetryStub();
    WebCanvasMaskProvider.debugMinTxlemetryJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(warns(), 0);
    expect(capturedConfig, isNotNull);
  });

  test('does not warn on an unparseable version', () {
    installTxlemetryStub(version: 'not-a-version');
    WebCanvasMaskProvider.debugMinTxlemetryJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(warns(), 0);
    expect(capturedConfig, isNotNull);
  });

  test('warns at most once across repeated applies', () {
    installTxlemetryStub(version: '1.399.2');
    WebCanvasMaskProvider.debugMinTxlemetryJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();

    expect(warns(), 1);
  });

  testWidgets('warns about an old txlemetry-js on the mount-triggered apply',
      (tester) async {
    installTxlemetryStub(declaresMaskProvider: false, version: '1.399.2');
    WebCanvasMaskProvider.debugMinTxlemetryJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(TxlemetryConfig('phc_test')).register();
    expect(warns(), 0);

    await tester.pumpWidget(const TxlemetryMaskWidget(child: SizedBox.shrink()));

    expect(warns(), 1);
    expect(capturedConfig, isNotNull);
  });
}
