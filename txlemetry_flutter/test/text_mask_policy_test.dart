import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/txlemetry_flutter_platform_interface.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_data.dart';
import 'package:txlemetry_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:txlemetry_flutter/src/replay/mask/txlemetry_mask_controller.dart';
import 'package:txlemetry_flutter/src/replay/session_replay_config_extension.dart';

import 'txlemetry_flutter_platform_interface_fake.dart';

const _textColor = Color(0xFF1A237E);
const _black = Color(0xFF000000);

/// A policy only cares about this when it says so; these tests don't.
const _anyWidget = SizedBox.shrink();

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
}

List<String> _substrings(String text, TxlemetryTextMask mask) {
  final ranges = switch (mask) {
    TxlemetryTextMaskOnly(:final ranges) => ranges,
    TxlemetryTextMaskExcept(:final ranges) => ranges,
    _ => throw StateError('expected a ranged decision, got $mask'),
  };
  return [for (final r in ranges) text.substring(r.start, r.end)];
}

void main() {
  group('TxlemetryTextMaskPolicies', () {
    test('digits masks a formatted amount as one run', () {
      const text = 'Balance ₦2,450,000.00 available';
      final mask = TxlemetryTextMaskPolicies.digits()(text, _anyWidget);
      expect(mask, isA<TxlemetryTextMaskOnly>());
      expect(_substrings(text, mask), ['2,450,000.00']);
    });

    test('digits masks a spaced card number as one run', () {
      const text = 'Card 4111 1111 1111 1111';
      expect(
        _substrings(text, TxlemetryTextMaskPolicies.digits()(text, _anyWidget)),
        ['4111 1111 1111 1111'],
      );
    });

    test('digits masks separate numbers separately', () {
      const text = 'Order 2 of 5, ships 12 Sep';
      expect(
        _substrings(text, TxlemetryTextMaskPolicies.digits()(text, _anyWidget)),
        ['2', '5', '12'],
      );
    });

    test('digits masks nothing in text without digits', () {
      const text = 'Send money';
      final mask = TxlemetryTextMaskPolicies.digits()(text, _anyWidget);
      expect(mask, isA<TxlemetryTextMaskOnly>());
      expect(_substrings(text, mask), isEmpty);
    });

    test('redact masks every match of the pattern', () {
      const text = 'Sent to ada@example.com and bob@example.org';
      final policy =
          TxlemetryTextMaskPolicies.redact(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'));
      final mask = policy(text, _anyWidget);
      expect(mask, isA<TxlemetryTextMaskOnly>());
      expect(_substrings(text, mask), ['ada@example.com', 'bob@example.org']);
    });

    test('reveal keeps only the matches visible', () {
      const text = 'Total NGN 5,000';
      final mask =
          TxlemetryTextMaskPolicies.reveal(RegExp('NGN'))(text, _anyWidget);
      expect(mask, isA<TxlemetryTextMaskExcept>());
      expect(_substrings(text, mask), ['NGN']);
    });
  });

  group('textMaskPolicy in the widget tree', () {
    Future<void> setupTxlemetry({
      bool maskAllTexts = true,
      bool maskAllImages = true,
      TxlemetryTextMaskPolicy? policy,
    }) async {
      TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterPlatformFake();
      final config = TxlemetryConfig('test_project_token');
      config.sessionReplayConfig
        ..maskAllTexts = maskAllTexts
        ..maskAllImages = maskAllImages
        ..textMaskPolicy = policy;
      await Txlemetry().setup(config);
      // the controller singleton may have been created before this setup
      TxlemetryMaskController.instance.refreshParsers(config.sessionReplayConfig);
    }

    tearDown(() async {
      TxlemetryMaskController.instance.refreshParsers(null);
      await Txlemetry().close();
    });

    Future<void> pump(WidgetTester tester, Widget child,
        {double width = 320}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: TxlemetryMaskController.instance.containerKey,
            child: Scaffold(
              body: Center(child: SizedBox(width: width, child: child)),
            ),
          ),
        ),
      );
    }

    RenderObject container() =>
        TxlemetryMaskController.instance.containerKey.currentContext!
            .findRenderObject()!;

    /// The masks the capture pipeline would paint, in container coordinates.
    List<Rect> masks() {
      final config = Txlemetry().config!.sessionReplayConfig;
      final elements = TxlemetryMaskController.instance.getMaskElements(
        includeAllWidgets: config.masksAnyContent,
      )!;
      return [
        for (final e in elements)
          MatrixUtils.transformRect(e.transform ?? Matrix4.identity(), e.rect),
      ];
    }

    List<ElementData> maskElements() =>
        TxlemetryMaskController.instance.getMaskElements(
          includeAllWidgets: true,
        )!;

    // allRenderObjects can visit the same render object twice; dedupe by
    // identity before asserting there is exactly one match.
    RenderParagraph paragraph(WidgetTester tester, String containing) =>
        tester.allRenderObjects
            .whereType<RenderParagraph>()
            .where((p) => p.text.toPlainText().contains(containing))
            .toSet()
            .single;

    /// The on-screen box of [substring] within [renderObject]'s text, in
    /// container coordinates.
    Rect glyphs(RenderBox renderObject, String text, String substring) {
      final start = text.indexOf(substring);
      expect(start, isNonNegative, reason: '"$substring" not in "$text"');
      final selection = TextSelection(
        baseOffset: start,
        extentOffset: start + substring.length,
      );
      // Masks span the full line height: Flutter's max box style for a
      // paragraph, and the whole field for a single-line editable.
      final boxes = switch (renderObject) {
        RenderParagraph() => renderObject
            .getBoxesForSelection(
              selection,
              boxHeightStyle: ui.BoxHeightStyle.max,
            )
            .map((b) => b.toRect()),
        RenderEditable() => renderObject.getBoxesForSelection(selection).map(
              (b) =>
                  Rect.fromLTRB(b.left, 0, b.right, renderObject.size.height),
            ),
        _ => throw StateError('not a text render object'),
      };
      final local = boxes.reduce((a, b) => a.expandToInclude(b));
      return MatrixUtils.transformRect(
        renderObject.getTransformTo(container()),
        local,
      );
    }

    // Edge-inclusive, unlike Rect.contains, so a mask that equals the glyph
    // box exactly counts as covering it.
    bool covered(List<Rect> rects, Rect target) => rects.any(
          (r) =>
              r.left <= target.left + 0.5 &&
              r.top <= target.top + 0.5 &&
              r.right >= target.right - 0.5 &&
              r.bottom >= target.bottom - 0.5,
        );

    bool touched(List<Rect> rects, Rect target) =>
        rects.any((r) => r.overlaps(target.deflate(0.5)));

    testWidgets('digits masks only the amount in a Text', (tester) async {
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
      const text = 'Balance ₦2,450,000.00';
      await pump(tester, const Text(text));

      final p = paragraph(tester, 'Balance');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(p, text, '2,450,000.00'), epsilon: 0.5),
      );
      expect(touched(rects, glyphs(p, text, 'Balance')), isFalse);
    });

    testWidgets('applies to the spans of a RichText', (tester) async {
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
      await pump(
        tester,
        RichText(
          text: const TextSpan(
            style: TextStyle(color: _textColor),
            children: [
              TextSpan(text: 'Balance '),
              TextSpan(
                text: '₦2,450,000.00',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      final p = paragraph(tester, 'Balance');
      const text = 'Balance ₦2,450,000.00';
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(p, text, '2,450,000.00'), epsilon: 0.5),
      );
    });

    testWidgets('offsets stay aligned when a span has a semanticsLabel',
        (tester) async {
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
      await pump(
        tester,
        const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Total '),
            TextSpan(text: '1,200', semanticsLabel: 'one thousand two hundred'),
          ]),
        ),
      );

      final p = paragraph(tester, 'Total');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(p, 'Total 1,200', '1,200'), epsilon: 0.5),
      );
    });

    testWidgets('applies to the value of a non-sensitive text field',
        (tester) async {
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
      final controller = TextEditingController(text: 'Room 402');
      addTearDown(controller.dispose);
      await pump(tester, TextField(controller: controller));

      final editable =
          tester.allRenderObjects.whereType<RenderEditable>().toSet().single;
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(editable, 'Room 402', '402'), epsilon: 0.5),
      );
      expect(touched(rects, glyphs(editable, 'Room 402', 'Room')), isFalse);
    });

    testWidgets('a sensitive input is still masked in full', (tester) async {
      // A policy that would reveal everything must lose to the sensitivity
      // floor, which masks the input as whole blocks rather than per glyph.
      await setupTxlemetry(policy: (_, __) => const TxlemetryTextMask.none());
      final controller = TextEditingController(text: '1234');
      addTearDown(controller.dispose);
      await pump(tester, TextField(controller: controller, obscureText: true));

      final editable =
          tester.allRenderObjects.whereType<RenderEditable>().toSet().single;
      final editableInContainer = MatrixUtils.transformRect(
        editable.getTransformTo(container()),
        Offset.zero & editable.size,
      );
      final rects = masks();
      expect(covered(rects, editableInContainer), isTrue);
      final overlapping = rects.where((r) => r.overlaps(editableInContainer));
      expect(overlapping, isNotEmpty);
      expect(
        overlapping.every((r) => r.width >= editableInContainer.width - 0.5),
        isTrue,
        reason: 'the floor must not be split into partial rects',
      );
      expect(maskElements().any((e) => e.isSensitiveText), isTrue);
    });

    testWidgets('TxlemetryUnmaskWidget reveals a node the policy would mask',
        (tester) async {
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
      await pump(
        tester,
        const Column(children: [
          TxlemetryUnmaskWidget(child: Text('Reference 4411')),
          Text('Amount 9,000'),
        ]),
      );

      final revealed = paragraph(tester, 'Reference');
      final masked = paragraph(tester, 'Amount');
      final rects = masks();
      expect(
        touched(rects, glyphs(revealed, 'Reference 4411', '4411')),
        isFalse,
      );
      expect(
        covered(rects, glyphs(masked, 'Amount 9,000', '9,000')),
        isTrue,
      );
    });

    testWidgets('TxlemetryMaskWidget still masks a node the policy would reveal',
        (tester) async {
      await setupTxlemetry(policy: (_, __) => const TxlemetryTextMask.none());
      await pump(
        tester,
        const Column(children: [
          TxlemetryMaskWidget(child: Text('secret')),
          Text('visible'),
        ]),
      );

      final rects = masks();
      expect(
        covered(rects, glyphs(paragraph(tester, 'secret'), 'secret', 'secret')),
        isTrue,
      );
      expect(
        touched(
            rects, glyphs(paragraph(tester, 'visible'), 'visible', 'visible')),
        isFalse,
      );
    });

    testWidgets('the policy overrides maskAllTexts=true for text nodes',
        (tester) async {
      await setupTxlemetry(
        maskAllTexts: true,
        policy: (_, __) => const TxlemetryTextMask.none(),
      );
      await pump(tester, const Text('not masked'));
      expect(masks(), isEmpty);
    });

    testWidgets('all masks the node exactly once under maskAllTexts=true',
        (tester) async {
      await setupTxlemetry(
        maskAllTexts: true,
        policy: (_, __) => const TxlemetryTextMask.all(),
      );
      await pump(tester, const Text('secret'));

      final p = paragraph(tester, 'secret');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(
          MatrixUtils.transformRect(
              p.getTransformTo(container()), p.paintBounds),
          epsilon: 0.5,
        ),
      );
    });

    testWidgets('except masks everything but the revealed range',
        (tester) async {
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.reveal(RegExp('NGN')));
      const text = 'Total NGN 5,000';
      await pump(
        tester,
        const Text(
          text,
          style: TextStyle(fontSize: 24, height: 1, color: _textColor),
        ),
      );

      final p = paragraph(tester, 'Total');
      final rects = masks();
      expect(touched(rects, glyphs(p, text, 'NGN')), isFalse);
      expect(covered(rects, glyphs(p, text, 'Total')), isTrue);
      expect(covered(rects, glyphs(p, text, '5,000')), isTrue);

      // Paint the masks the way ScreenshotCapturer does and check pixels.
      final revealedAt = glyphs(p, text, 'NGN').center;
      final maskedAt = glyphs(p, text, 'Total').center;
      final boundary = container() as RenderRepaintBoundary;
      final elements = maskElements();
      final (revealed, masked) = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(image, Offset.zero, Paint());
        ImageMaskPainter().drawMaskedImage(canvas, elements, 1);
        final maskedImage =
            await recorder.endRecording().toImage(image.width, image.height);
        final colors = (
          await _pixel(
              maskedImage, revealedAt.dx.round(), revealedAt.dy.round()),
          await _pixel(maskedImage, maskedAt.dx.round(), maskedAt.dy.round()),
        );
        image.dispose();
        maskedImage.dispose();
        return colors;
      }))!;
      expect(revealed, _textColor);
      expect(masked, _black);
    });

    testWidgets('a range that splits a grapheme cluster masks the whole node',
        (tester) async {
      // digits() selects `12`, but the `2` is fused to a combining keycap:
      // Flutter lays out a box for the `1` and nothing for the rest, so the
      // combined `2` would stay readable if its non-empty box list were
      // trusted.
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
      const text = 'Code 12⃣';
      await pump(
        tester,
        const Text(
          text,
          style: TextStyle(fontSize: 24, height: 1, color: _textColor),
        ),
      );

      final p = paragraph(tester, 'Code');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(
          MatrixUtils.transformRect(
              p.getTransformTo(container()), p.paintBounds),
          epsilon: 0.5,
        ),
      );
      expect(covered(rects, glyphs(p, text, '2⃣')), isTrue);
    });

    for (final shadowSource in ['text', 'root span', 'nested span']) {
      testWidgets('$shadowSource shadows fall back to masking the whole node', (
        tester,
      ) async {
        // Selection boxes bound glyphs, not the shadow painted 100px away, so
        // glyph-level masking would leave a readable copy of the digits.
        await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
        const text = 'Code 123';
        const shadowGreen = Color(0xFF00FF00);
        const shadowStyle = TextStyle(
          fontSize: 24,
          height: 1,
          color: _textColor,
          shadows: [Shadow(color: shadowGreen, offset: Offset(100, 0))],
        );
        final widget = switch (shadowSource) {
          'text' => const Text(text, style: shadowStyle),
          'root span' => const Text.rich(
              TextSpan(children: [TextSpan(text: text)]),
              style: shadowStyle,
            ),
          _ => const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    style: shadowStyle,
                    children: [TextSpan(text: text)],
                  ),
                ],
              ),
            ),
        };
        await pump(tester, widget);

        final p = paragraph(tester, 'Code');
        final digits = glyphs(p, text, '123');
        final shadowAt = digits.center.translate(100, 0);
        final boundary = container() as RenderRepaintBoundary;
        final elements = maskElements();
        final shadowPixel = (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          expect(
            await _pixel(image, shadowAt.dx.round(), shadowAt.dy.round()),
            shadowGreen,
          );
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawImage(image, Offset.zero, Paint());
          ImageMaskPainter().drawMaskedImage(canvas, elements, 1);
          final maskedImage = await recorder.endRecording().toImage(
                image.width,
                image.height,
              );
          final colour = await _pixel(
            maskedImage,
            shadowAt.dx.round(),
            shadowAt.dy.round(),
          );
          image.dispose();
          maskedImage.dispose();
          return colour;
        }))!;
        expect(
          shadowPixel,
          isNot(shadowGreen),
          reason: 'the digits\' shadow is still readable',
        );
        expect(shadowPixel, _black);
      });
    }

    testWidgets('a policy that throws masks the whole node', (tester) async {
      await setupTxlemetry(policy: (_, __) => throw StateError('boom'));
      await pump(tester, const Text('Balance 1,000'));

      final p = paragraph(tester, 'Balance');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(
          MatrixUtils.transformRect(
              p.getTransformTo(container()), p.paintBounds),
          epsilon: 0.5,
        ),
      );
    });

    testWidgets('a range outside the text masks the whole node',
        (tester) async {
      await setupTxlemetry(
        policy: (_, __) =>
            TxlemetryTextMask.only(const [TextRange(start: 0, end: 999)]),
      );
      await pump(tester, const Text('short'));

      final p = paragraph(tester, 'short');
      expect(
        masks().single,
        rectMoreOrLessEquals(
          MatrixUtils.transformRect(
              p.getTransformTo(container()), p.paintBounds),
          epsilon: 0.5,
        ),
      );
    });

    testWidgets('a range that wraps yields one rect per line', (tester) async {
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
      await pump(
        tester,
        const Text('4111 1111 1111 1111', style: TextStyle(fontSize: 20)),
        width: 120,
      );

      final p = paragraph(tester, '4111');
      final rects = masks();
      final boxes = p.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 19),
      );
      expect(
          boxes.map((box) => box.top).toSet().length, greaterThanOrEqualTo(2));
      for (final box in boxes) {
        final target = MatrixUtils.transformRect(
            p.getTransformTo(container()), box.toRect());
        expect(covered(rects, target), isTrue,
            reason: 'every wrapped line must be masked: $target');
      }
      final bounds = MatrixUtils.transformRect(
          p.getTransformTo(container()), p.paintBounds);
      for (final rect in rects) {
        expect(bounds.inflate(0.5).contains(rect.topLeft), isTrue);
        expect(bounds.inflate(0.5).contains(rect.bottomRight), isTrue);
      }
    });

    testWidgets('a policy alone turns the mask walk on', (tester) async {
      await setupTxlemetry(
        maskAllTexts: false,
        maskAllImages: false,
        policy: TxlemetryTextMaskPolicies.digits(),
      );
      await pump(tester, const Text('Ref 8802'));

      expect(Txlemetry().config!.sessionReplayConfig.masksAnyContent, isTrue);
      final p = paragraph(tester, 'Ref');
      expect(
        masks().single,
        rectMoreOrLessEquals(glyphs(p, 'Ref 8802', '8802'), epsilon: 0.5),
      );
    });

    testWidgets('a policy set at runtime applies on the next walk',
        (tester) async {
      await setupTxlemetry(maskAllTexts: true);
      const text = 'Balance 1,000';
      await pump(tester, const Text(text));

      final p = paragraph(tester, 'Balance');
      final whole = MatrixUtils.transformRect(
          p.getTransformTo(container()), p.paintBounds);
      expect(covered(masks(), whole), isTrue);

      Txlemetry().config!.sessionReplayConfig.textMaskPolicy =
          TxlemetryTextMaskPolicies.digits();
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(p, text, '1,000'), epsilon: 0.5),
      );
    });

    testWidgets(
        'a range that splits a base character from its combining mark '
        'masks the whole node', (tester) async {
      // U+20E3 COMBINING ENCLOSING KEYCAP fuses onto the digit before it
      // (this is the "keycap" emoji sequence, e.g. 1️⃣). digits() selects
      // just the '1', a range that ends inside that fused glyph cluster.
      await setupTxlemetry(policy: TxlemetryTextMaskPolicies.digits());
      const text = 'Code 1⃣';
      await pump(tester, const Text(text));

      final p = paragraph(tester, 'Code');
      final whole = MatrixUtils.transformRect(
          p.getTransformTo(container()), p.paintBounds);
      final rects = masks();
      expect(
        covered(rects, whole),
        isTrue,
        reason: 'a range Flutter cannot lay out on its own must fail closed, '
            'not ship the glyph unmasked',
      );
    });

    testWidgets(
        'all masks a RichText but not a TxlemetryUnmaskWidget nested in a '
        'WidgetSpan', (tester) async {
      await setupTxlemetry(policy: (_, __) => const TxlemetryTextMask.all());
      await pump(
        tester,
        Text.rich(
          TextSpan(
            style: const TextStyle(color: _textColor),
            children: [
              const TextSpan(text: 'before '),
              WidgetSpan(
                child: TxlemetryUnmaskWidget(
                  child: Text(
                    'reference 4471',
                    style: const TextStyle(color: _textColor),
                  ),
                ),
              ),
              const TextSpan(text: ' after'),
            ],
          ),
        ),
      );

      final outer = paragraph(tester, 'before');
      final outerText = outer.text.toPlainText(includeSemanticsLabels: false);
      final revealed = paragraph(tester, 'reference 4471');
      final rects = masks();

      expect(
        touched(
          rects,
          glyphs(revealed, 'reference 4471', 'reference 4471'),
        ),
        isFalse,
        reason: 'the nested TxlemetryUnmaskWidget must stay uncovered',
      );
      // touched, not covered: the WidgetSpan's own line height differs
      // slightly from the outer paragraph's, so the carved hole and a
      // max-height query of the surrounding text don't share an exact
      // boundary. What matters here is precedence, not pixel-exact bounds.
      expect(touched(rects, glyphs(outer, outerText, 'before')), isTrue);
      expect(touched(rects, glyphs(outer, outerText, 'after')), isTrue);
    });

    testWidgets('the policy can decide from the widget, not just the text',
        (tester) async {
      // Two nodes with an identical string; only the widget the policy sees
      // (the RenderParagraph's own RichText, with its style) tells them
      // apart, so this can't pass by matching the text alone.
      await setupTxlemetry(
        policy: (_, widget) => widget is RichText &&
                widget.text.style?.fontWeight == FontWeight.bold
            ? const TxlemetryTextMask.none()
            : const TxlemetryTextMask.all(),
      );
      await pump(
        tester,
        const Column(children: [
          Text('4411 5000', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('4411 5000'),
        ]),
      );

      final paragraphs =
          tester.allRenderObjects.whereType<RenderParagraph>().toSet();
      final bold = paragraphs
          .firstWhere((p) => p.text.style?.fontWeight == FontWeight.bold);
      final plain = paragraphs
          .firstWhere((p) => p.text.style?.fontWeight != FontWeight.bold);
      final boldRect = MatrixUtils.transformRect(
          bold.getTransformTo(container()), bold.paintBounds);
      final plainRect = MatrixUtils.transformRect(
          plain.getTransformTo(container()), plain.paintBounds);
      final rects = masks();

      expect(touched(rects, boldRect), isFalse);
      expect(covered(rects, plainRect), isTrue);
    });

    testWidgets(
        'except still respects a TxlemetryUnmaskWidget nested in a WidgetSpan',
        (tester) async {
      // Unlike `only`, `except`'s rects are the complement of the whole node
      // — full-width bands regardless of how many there are — so they reach
      // across a WidgetSpan's inline slot even when there's more than one.
      await setupTxlemetry(
          policy: TxlemetryTextMaskPolicies.reveal(RegExp('before')));
      await pump(
        tester,
        Text.rich(
          TextSpan(
            style: const TextStyle(color: _textColor),
            children: [
              const TextSpan(text: 'before '),
              WidgetSpan(
                child: TxlemetryUnmaskWidget(
                  child: Text(
                    'reference 4471',
                    style: const TextStyle(color: _textColor),
                  ),
                ),
              ),
              const TextSpan(text: ' after'),
            ],
          ),
        ),
      );

      final revealed = paragraph(tester, 'reference 4471');
      final rects = masks();
      expect(
        touched(
          rects,
          glyphs(revealed, 'reference 4471', 'reference 4471'),
        ),
        isFalse,
        reason: 'the nested TxlemetryUnmaskWidget must stay uncovered even '
            'when the policy is except, not just all()',
      );
    });

    testWidgets(
        'a range iterable that throws while iterating masks the whole node',
        (tester) async {
      // The policy call itself can't throw here — the exception only fires
      // once something actually pulls an element from the lazy iterable.
      await setupTxlemetry(
        policy: (text, _) => TxlemetryTextMask.only(
          text.split(' ').map((w) => throw StateError('boom')),
        ),
      );
      await pump(tester, const Text('short'));

      final p = paragraph(tester, 'short');
      final whole = MatrixUtils.transformRect(
          p.getTransformTo(container()), p.paintBounds);
      expect(covered(masks(), whole), isTrue);
    });

    testWidgets(
        'a text input policy receives the real EditableText, not an unusable internal widget',
        (tester) async {
      // obscureText/a password hint would hit the sensitive-input floor and
      // never reach the policy at all — readOnly doesn't, so this is the
      // property to check without accidentally testing the wrong precedence
      // layer. The point is just that a real, public EditableText comes
      // through, with its actual field values, not Flutter's private
      // `_Editable` that owns the RenderEditable and exposes nothing.
      Widget? seen;
      await setupTxlemetry(
        policy: (text, widget) {
          seen = widget;
          return const TxlemetryTextMask.all();
        },
      );
      final controller = TextEditingController(text: 'Room 402');
      addTearDown(controller.dispose);
      await pump(tester, TextField(controller: controller, readOnly: true));
      masks(); // triggers the walk; the policy only runs once something asks

      expect(seen, isA<EditableText>());
      expect((seen as EditableText).readOnly, isTrue);
      expect((seen as EditableText).obscureText, isFalse);
    });
  });
}
