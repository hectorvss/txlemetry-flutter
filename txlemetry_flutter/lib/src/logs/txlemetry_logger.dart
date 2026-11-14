import 'package:meta/meta.dart';

import 'txlemetry_log_severity.dart';

/// Signature used internally by [TxlemetryLogger] to forward a record to the
/// capture path. Not part of the public API.
@internal
typedef CaptureLog = Future<void> Function(
  String body,
  TxlemetryLogSeverity level,
  Map<String, Object>? attributes,
);

/// Per-level convenience facade for capturing structured logs.
///
/// Obtain it via `Txlemetry().logger`. Each helper captures a record at its
/// severity and is equivalent to calling `Txlemetry().captureLog(...)` with the
/// matching `level`.
///
/// **Example:**
/// ```dart
/// Txlemetry().logger.info('checkout completed', {'order_id': 'ord_789'});
/// Txlemetry().logger.error('payment failed', {'error_code': 'E001'});
/// ```
class TxlemetryLogger {
  final CaptureLog _capture;

  /// Creates a logger that forwards records through [capture].
  ///
  /// For internal use — obtain the logger via `Txlemetry().logger`.
  @internal
  TxlemetryLogger(CaptureLog capture) : _capture = capture;

  /// Captures a [TxlemetryLogSeverity.trace] record.
  Future<void> trace(String body, [Map<String, Object>? attributes]) =>
      _capture(body, TxlemetryLogSeverity.trace, attributes);

  /// Captures a [TxlemetryLogSeverity.debug] record.
  Future<void> debug(String body, [Map<String, Object>? attributes]) =>
      _capture(body, TxlemetryLogSeverity.debug, attributes);

  /// Captures a [TxlemetryLogSeverity.info] record.
  Future<void> info(String body, [Map<String, Object>? attributes]) =>
      _capture(body, TxlemetryLogSeverity.info, attributes);

  /// Captures a [TxlemetryLogSeverity.warn] record.
  Future<void> warn(String body, [Map<String, Object>? attributes]) =>
      _capture(body, TxlemetryLogSeverity.warn, attributes);

  /// Captures a [TxlemetryLogSeverity.error] record.
  Future<void> error(String body, [Map<String, Object>? attributes]) =>
      _capture(body, TxlemetryLogSeverity.error, attributes);

  /// Captures a [TxlemetryLogSeverity.fatal] record.
  Future<void> fatal(String body, [Map<String, Object>? attributes]) =>
      _capture(body, TxlemetryLogSeverity.fatal, attributes);
}
