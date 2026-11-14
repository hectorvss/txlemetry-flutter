/// Content type for text-based survey elements
enum TxlemetryDisplaySurveyTextContentType {
  /// Content should be rendered as HTML
  html(0),

  /// Content should be rendered as plain text
  text(1);

  const TxlemetryDisplaySurveyTextContentType(this.value);

  final int value;

  /// Create from raw int value
  static TxlemetryDisplaySurveyTextContentType fromInt(int value) {
    return TxlemetryDisplaySurveyTextContentType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TxlemetryDisplaySurveyTextContentType.text, // Default to text
    );
  }
}
