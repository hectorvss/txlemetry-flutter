import 'dart:async';

import '../txlemetry_event.dart';
import '../util/logging.dart';

/// Runs a single beforeSend [callback] against [record], awaiting an async
/// result. Returns the (possibly modified) record, or `null` to drop it.
///
/// A throw propagates. [applyBeforeSend] is the event policy: it drops the
/// event. Log capture drops the record in its own loop.
Future<T?> runBeforeSend<T>(
  FutureOr<T?> Function(T) callback,
  T record,
) async {
  final result = callback(record);
  if (result is Future<T?>) {
    return await result;
  }
  return result;
}

/// Runs [callbacks] in order against [event].
///
/// A null return drops the event and skips the rest of the list. A throw drops
/// the event too.
Future<TxlemetryEvent?> applyBeforeSend(
  List<FutureOr<TxlemetryEvent?> Function(TxlemetryEvent)> callbacks,
  TxlemetryEvent event,
) async {
  if (callbacks.isEmpty) return event;

  for (final callback in callbacks) {
    try {
      final result = await runBeforeSend<TxlemetryEvent>(callback, event);
      if (result == null) return null;
      event = result;
    } catch (e) {
      printIfDebug(
        '[Txlemetry] Warning: beforeSend callback threw an exception; dropping event: $e',
      );
      return null;
    }
  }
  return event;
}
