import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/surveys/models/txlemetry_display_survey_appearance.dart';
import 'package:txlemetry_flutter/src/surveys/models/survey_appearance.dart';
import 'package:txlemetry_flutter/src/surveys/widgets/survey_choice_button.dart';

void main() {
  final darkTheme = SurveyAppearance.fromTxlemetry(
    const TxlemetryDisplaySurveyAppearance(backgroundColor: '#1a1a2e'),
  );

  for (final isSelected in [true, false]) {
    testWidgets('choice label follows theme text color (selected=$isSelected)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SurveyChoiceButton(
            label: 'Option',
            isSelected: isSelected,
            onTap: () {},
            appearance: darkTheme,
          ),
        ),
      ));

      final text = tester.widget<Text>(find.text('Option'));
      final expected = isSelected
          ? darkTheme.choiceButtonTextColor
          : darkTheme.choiceButtonTextColor.withValues(alpha: 0.5);
      expect(darkTheme.choiceButtonTextColor, Colors.white);
      expect(text.style?.color, expected);
    });
  }
}
