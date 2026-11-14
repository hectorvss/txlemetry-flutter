import 'package:flutter/foundation.dart';
import 'txlemetry_survey_question_type.dart';
import 'txlemetry_display_survey_text_content_type.dart';

/// Base class for all survey questions
@immutable
abstract class TxlemetryDisplaySurveyQuestion {
  const TxlemetryDisplaySurveyQuestion({
    required this.id,
    required this.type,
    required this.question,
    this.description,
    this.descriptionContentType = TxlemetryDisplaySurveyTextContentType.text,
    this.optional = false,
    this.buttonText,
  });

  final String id;
  final TxlemetrySurveyQuestionType type;
  final String question;
  final String? description;
  final TxlemetryDisplaySurveyTextContentType descriptionContentType;
  final bool optional;
  final String? buttonText;
}
