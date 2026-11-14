import 'package:flutter/foundation.dart';
import 'txlemetry_survey_question_type.dart';
import 'txlemetry_display_survey_question.dart';

/// Link question type
@immutable
class TxlemetryDisplayLinkQuestion extends TxlemetryDisplaySurveyQuestion {
  const TxlemetryDisplayLinkQuestion({
    required super.id,
    required super.question,
    required this.link,
    super.description,
    super.descriptionContentType,
    super.optional,
    super.buttonText,
  }) : super(type: TxlemetrySurveyQuestionType.link);

  final String link;
}
