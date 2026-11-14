import 'package:flutter/foundation.dart';
import 'txlemetry_survey_question_type.dart';
import 'txlemetry_display_survey_question.dart';

/// Open text question type
@immutable
class TxlemetryDisplayOpenQuestion extends TxlemetryDisplaySurveyQuestion {
  const TxlemetryDisplayOpenQuestion({
    required super.id,
    required super.question,
    super.description,
    super.descriptionContentType,
    super.optional,
    super.buttonText,
  }) : super(type: TxlemetrySurveyQuestionType.openText);
}
