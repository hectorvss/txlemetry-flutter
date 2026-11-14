import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txlemetry_flutter/src/surveys/models/txlemetry_display_survey.dart';
import 'package:txlemetry_flutter/src/surveys/models/survey_appearance.dart';
import 'package:txlemetry_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:txlemetry_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  testWidgets('optional multiple choice skip submits null', (tester) async {
    final responses = <Object?>[];
    final survey = TxlemetryDisplaySurvey.fromDict({
      'id': 'survey-1',
      'name': 'Choices',
      'questions': [
        {
          'type': 'multiple_choice',
          'question': 'Which apply?',
          'isOptional': true,
          'choices': ['A', 'B'],
          'hasOpenChoice': false,
          'shuffleOptions': false,
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SurveyBottomSheet(
          survey: survey,
          appearance: SurveyAppearance.fromTxlemetry(survey.appearance),
          onShown: (_) {},
          onClosed: (_) {},
          onResponse: (_, index, response) async {
            responses.add(response);
            return TxlemetrySurveyNextQuestion(
              questionIndex: index,
              isSurveyCompleted: true,
            );
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(responses, [null]);
  });
}
