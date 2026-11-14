// ignore: unnecessary_import
import 'package:meta/meta.dart';

/// A wrapper exception that carries Txlemetry-specific metadata
@internal
class TxlemetryException implements Exception {
  /// The original exception/error that was wrapped
  final Object source;
  final String mechanism;
  final bool handled;

  const TxlemetryException({
    required this.source,
    required this.mechanism,
    this.handled = false,
  });
}
