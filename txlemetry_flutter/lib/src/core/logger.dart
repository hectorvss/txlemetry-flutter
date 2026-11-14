import 'package:flutter/foundation.dart';

/// Logger used internally by Txlemetry.
class CoreLogger {
  static const _prefix = '[Txlemetry]';

  final void Function(void Function()) _maybeCall;

  CoreLogger(this._maybeCall);

  void info(Object? message, [Object? arg]) {
    _maybeCall(() =>
        debugPrint('$_prefix [INFO] $message${arg != null ? ' $arg' : ''}'));
  }

  void warn(Object? message, [Object? arg]) {
    _maybeCall(() =>
        debugPrint('$_prefix [WARN] $message${arg != null ? ' $arg' : ''}'));
  }

  void error(Object? message, [Object? arg]) {
    _maybeCall(() =>
        debugPrint('$_prefix [ERROR] $message${arg != null ? ' $arg' : ''}'));
  }
}
