import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/replay/mask/txlemetry_platform_view.dart';
import 'package:txlemetry_flutter/src/replay/screenshot/screenshot_capturer.dart';

void main() {
  group('resolvePrivacyPolicyForElement — privacy inheritance', () {
    testWidgets('unwrapped widget inherits the default mask policy',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(key: Key('leaf')),
        ),
      );
      final element = tester.element(find.byKey(const Key('leaf')));
      final policy = resolvePrivacyPolicyForElement(
          element, TxlemetryPlatformViewPrivacy.mask);
      expect(policy, TxlemetryPlatformViewPrivacy.mask);
    });

    testWidgets('capture wrapper overrides an inherited mask policy',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: TxlemetryPlatformView(
            key: Key('wrapper'),
            privacy: TxlemetryPlatformViewPrivacy.capture,
            child: SizedBox(),
          ),
        ),
      );
      final element = tester.element(find.byKey(const Key('wrapper')));
      final policy = resolvePrivacyPolicyForElement(
          element, TxlemetryPlatformViewPrivacy.mask);
      expect(policy, TxlemetryPlatformViewPrivacy.capture);
    });

    testWidgets('mask wrapper overrides an inherited capture policy',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: TxlemetryPlatformView(
            key: Key('wrapper'),
            privacy: TxlemetryPlatformViewPrivacy.mask,
            child: SizedBox(),
          ),
        ),
      );
      final element = tester.element(find.byKey(const Key('wrapper')));
      final policy = resolvePrivacyPolicyForElement(
          element, TxlemetryPlatformViewPrivacy.capture);
      expect(policy, TxlemetryPlatformViewPrivacy.mask);
    });

    testWidgets('innermost nested wrapper wins over outer wrapper',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: TxlemetryPlatformView(
            key: Key('outer'),
            privacy: TxlemetryPlatformViewPrivacy.mask,
            child: TxlemetryPlatformView(
              key: Key('inner'),
              privacy: TxlemetryPlatformViewPrivacy.capture,
              child: SizedBox(key: Key('leaf')),
            ),
          ),
        ),
      );

      final outerElement = tester.element(find.byKey(const Key('outer')));
      final outerPolicy = resolvePrivacyPolicyForElement(
          outerElement, TxlemetryPlatformViewPrivacy.capture);
      expect(outerPolicy, TxlemetryPlatformViewPrivacy.mask);

      final innerElement = tester.element(find.byKey(const Key('inner')));
      final innerPolicy =
          resolvePrivacyPolicyForElement(innerElement, outerPolicy);
      expect(innerPolicy, TxlemetryPlatformViewPrivacy.capture);

      final leafElement = tester.element(find.byKey(const Key('leaf')));
      final leafPolicy =
          resolvePrivacyPolicyForElement(leafElement, innerPolicy);
      expect(leafPolicy, TxlemetryPlatformViewPrivacy.capture);
    });
  });
}
