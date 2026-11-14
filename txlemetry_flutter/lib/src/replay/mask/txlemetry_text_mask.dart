import 'dart:ui' show TextRange;

import 'package:flutter/widgets.dart' show Widget;

/// What session replay masks inside one text node.
///
/// A [TxlemetryTextMaskPolicy] returns one of these for every plain `Text`,
/// `RichText`, and non-sensitive text input that a replay frame captures.
/// Ranges are character offsets into the node's rendered string, exactly as
/// it was passed to the policy. Build one with the named constructors, or
/// match on the four subtypes.
sealed class TxlemetryTextMask {
  const TxlemetryTextMask._();

  /// Mask the whole node.
  const factory TxlemetryTextMask.all() = TxlemetryTextMaskAll;

  /// Leave the whole node visible.
  const factory TxlemetryTextMask.none() = TxlemetryTextMaskNone;

  /// Mask only [ranges]; the rest of the node stays visible.
  ///
  /// An empty [ranges] masks nothing.
  const factory TxlemetryTextMask.only(Iterable<TextRange> ranges) =
      TxlemetryTextMaskOnly;

  /// Mask the whole node except [ranges].
  ///
  /// An empty [ranges] masks the whole node.
  const factory TxlemetryTextMask.except(Iterable<TextRange> ranges) =
      TxlemetryTextMaskExcept;
}

/// [TxlemetryTextMask.all]: the whole node is masked.
final class TxlemetryTextMaskAll extends TxlemetryTextMask {
  /// Creates a decision that masks the whole node.
  const TxlemetryTextMaskAll() : super._();
}

/// [TxlemetryTextMask.none]: the whole node stays visible.
final class TxlemetryTextMaskNone extends TxlemetryTextMask {
  /// Creates a decision that leaves the whole node visible.
  const TxlemetryTextMaskNone() : super._();
}

/// [TxlemetryTextMask.only]: only [ranges] are masked.
final class TxlemetryTextMaskOnly extends TxlemetryTextMask {
  /// Creates a decision that masks only [ranges].
  const TxlemetryTextMaskOnly(this.ranges) : super._();

  /// The character ranges to mask.
  final Iterable<TextRange> ranges;
}

/// [TxlemetryTextMask.except]: everything but [ranges] is masked.
final class TxlemetryTextMaskExcept extends TxlemetryTextMask {
  /// Creates a decision that masks everything except [ranges].
  const TxlemetryTextMaskExcept(this.ranges) : super._();

  /// The character ranges to leave visible.
  final Iterable<TextRange> ranges;
}

/// Decides what to mask in a text node, given its rendered string and the
/// widget that produced it.
///
/// Set one on `TxlemetrySessionReplayConfig.textMaskPolicy`. [widget] is the
/// `RichText` or `EditableText` that actually produced the render object —
/// not the outer `Text`/`TextField` an app writes, which Flutter composes
/// away — so inspect its style, its `InlineSpan`, or (for inputs)
/// properties like `obscureText` and `readOnly` to decide by more than the
/// string. It is called on the UI thread for every captured text node, so
/// keep it fast and free of side effects. Throwing masks the whole node.
typedef TxlemetryTextMaskPolicy = TxlemetryTextMask Function(
  String text,
  Widget widget,
);

/// Ready-made [TxlemetryTextMaskPolicy] implementations.
abstract final class TxlemetryTextMaskPolicies {
  /// Masks every run of digits and leaves the surrounding words visible.
  ///
  /// A run may contain grouping punctuation (`,` `.` `-`) and spaces between
  /// its digits, so a formatted amount or card number is one mask:
  /// `₦2,450,000.00` and `4111 1111 1111 1111` are each masked in full, and
  /// in `Order 2 of 5` only the `2` and the `5` are.
  static TxlemetryTextMaskPolicy digits() => redact(_digitRun);

  /// Masks every match of [pattern] and leaves the rest of the node visible.
  ///
  /// ```dart
  /// // Hide anything that looks like an email address.
  /// TxlemetryTextMaskPolicies.redact(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'))
  /// ```
  static TxlemetryTextMaskPolicy redact(RegExp pattern) =>
      (text, widget) => TxlemetryTextMask.only(_matches(pattern, text));

  /// Masks the whole node except the matches of [pattern].
  ///
  /// ```dart
  /// // Keep currency codes readable inside otherwise masked amounts.
  /// TxlemetryTextMaskPolicies.reveal(RegExp(r'\b(NGN|USD|GBP)\b'))
  /// ```
  static TxlemetryTextMaskPolicy reveal(RegExp pattern) =>
      (text, widget) => TxlemetryTextMask.except(_matches(pattern, text));

  static final RegExp _digitRun = RegExp(r'\d[\d.,\- ]*\d|\d');

  static Iterable<TextRange> _matches(RegExp pattern, String text) => pattern
      .allMatches(text)
      .map((match) => TextRange(start: match.start, end: match.end));
}
