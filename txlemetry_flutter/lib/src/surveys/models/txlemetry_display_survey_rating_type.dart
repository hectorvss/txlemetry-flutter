/// Rating type for survey questions
enum TxlemetryDisplaySurveyRatingType {
  number(0),
  emoji(1);

  const TxlemetryDisplaySurveyRatingType(this.value);
  final int value;

  static TxlemetryDisplaySurveyRatingType fromInt(int type) {
    return TxlemetryDisplaySurveyRatingType.values.firstWhere(
      (e) => e.value == type,
      orElse: () => TxlemetryDisplaySurveyRatingType.number,
    );
  }

  @override
  String toString() => name;
}
