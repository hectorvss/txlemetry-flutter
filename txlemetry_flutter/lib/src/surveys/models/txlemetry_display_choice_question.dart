import 'package:flutter/foundation.dart';
import 'txlemetry_survey_question_type.dart';
import 'txlemetry_display_survey_question.dart';

/// choice question type
@immutable
class TxlemetryDisplayChoiceQuestion extends TxlemetryDisplaySurveyQuestion {
  const TxlemetryDisplayChoiceQuestion({
    required super.id,
    required super.question,
    required this.choices,
    required this.isMultipleChoice,
    this.hasOpenChoice = false,
    this.shuffleOptions = false,
    this.skipSubmitButton = false,
    super.description,
    super.descriptionContentType,
    super.optional,
    super.buttonText,
  }) : super(
          type: isMultipleChoice
              ? TxlemetrySurveyQuestionType.multipleChoice
              : TxlemetrySurveyQuestionType.singleChoice,
        );

  final bool skipSubmitButton;
  final List<String> choices;
  final bool isMultipleChoice;
  final bool hasOpenChoice;
  final bool shuffleOptions;
}
