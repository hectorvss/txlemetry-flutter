import 'txlemetry_display_survey.dart';

/// Called when a survey is shown to the user
typedef OnSurveyShown = void Function(TxlemetryDisplaySurvey survey);

/// Called when a user responds to a survey question
typedef OnSurveyResponse = Future<TxlemetrySurveyNextQuestion?> Function(
  TxlemetryDisplaySurvey survey,
  int questionIndex,
  Object? response,
);

/// Called when a survey is closed
typedef OnSurveyClosed = void Function(TxlemetryDisplaySurvey survey);

/// Represents the next question to show in a survey
class TxlemetrySurveyNextQuestion {
  const TxlemetrySurveyNextQuestion({
    required this.questionIndex,
    required this.isSurveyCompleted,
  });

  final int questionIndex;
  final bool isSurveyCompleted;
}
