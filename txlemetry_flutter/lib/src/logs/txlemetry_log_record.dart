import 'txlemetry_log_severity.dart';

/// Represents a log record that can be modified or dropped before it is sent.
///
/// This class is passed to the before-send callbacks registered via
/// [TxlemetryLogsConfig.beforeSend] to allow modification of log records before
/// they are forwarded to the native SDK.
class TxlemetryLogRecord {
  /// The log message body.
  String body;

  /// The severity level of the record.
  TxlemetryLogSeverity level;

  /// User-provided attributes for this record.
  ///
  /// Note: Auto-captured context (distinct id, session id, screen name, app
  /// state, active feature flags) is added by the native SDK at a later stage
  /// and is not available in this map.
  Map<String, Object>? attributes;

  /// Creates a log record passed to a before-send callback.
  ///
  /// The [body] is the log message.
  ///
  /// The [level] is the severity, defaulting to [TxlemetryLogSeverity.info].
  ///
  /// The optional [attributes] are per-record attributes that can be amended
  /// before capture.
  TxlemetryLogRecord({
    required this.body,
    this.level = TxlemetryLogSeverity.info,
    this.attributes,
  });

  @override
  String toString() {
    return 'TxlemetryLogRecord(body: $body, level: ${level.name}, attributes: $attributes)';
  }
}
