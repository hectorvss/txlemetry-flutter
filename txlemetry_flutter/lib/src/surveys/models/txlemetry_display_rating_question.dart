import 'package:flutter/foundation.dart';
import 'txlemetry_survey_question_type.dart';
import 'txlemetry_display_survey_question.dart';
import 'txlemetry_display_survey_rating_type.dart';

/// Rating question type
@immutable
class TxlemetryDisplayRatingQuestion extends TxlemetryDisplaySurveyQuestion {
  const TxlemetryDisplayRatingQuestion({
    required super.id,
    required super.question,
    required this.ratingType,
    required this.scaleLowerBound,
    required this.scaleUpperBound,
    required this.lowerBoundLabel,
    required this.upperBoundLabel,
    this.skipSubmitButton = false,
    super.description,
    super.descriptionContentType,
    super.optional,
    super.buttonText,
  }) : super(type: TxlemetrySurveyQuestionType.rating);

  final bool skipSubmitButton;
  final TxlemetryDisplaySurveyRatingType ratingType;
  final int scaleLowerBound;
  final int scaleUpperBound;
  final String lowerBoundLabel;
  final String upperBoundLabel;
}
