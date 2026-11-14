import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

import 'canvas_mask_registration_io.dart'
    if (dart.library.js_interop) 'canvas_mask_registration_web.dart';

/// Masks a widget subtree in Txlemetry session replay snapshots.
///
/// Wrap sensitive UI with [TxlemetryMaskWidget] to hide that area in captured
/// screenshots, regardless of the global session replay masking settings.
/// `TxlemetryUnmaskWidget` overrides this mask in either nesting order, except
/// for sensitive text inputs. See that widget's documentation for geometry
/// limits when revealing part of an enclosing mask.
///
/// **Flutter web:** the canvas is masked by txlemetry-js rather than by this
/// plugin, so the first [TxlemetryMaskWidget] or `TxlemetryUnmaskWidget` to mount
/// turns canvas masking on —
/// which restarts an in-flight recording once, because masking also excludes
/// the Flutter semantics DOM tree via `blockSelector`, and txlemetry-js only
/// reads that when recording starts. Canvas recording itself must be enabled
/// separately — either with `captureCanvas: { recordCanvas: true }` as shown
/// below, or with the canvas capture toggle in your project's session replay
/// settings. Frames captured before that first mount are recorded unmasked;
/// to cover the window between `txlemetry.init` and Flutter booting, declare
/// `session_recording: { captureCanvas: { recordCanvas: true },
/// canvasCapture: { maskRegionsFn: () => null } }`
/// in your `txlemetry.init` call — until this plugin takes over, those frames are
/// skipped instead of recorded. Your app must be wrapped in `TxlemetryWidget`,
/// and every mask/unmask widget must sit inside it — otherwise canvas frames
/// are skipped instead of recorded unmasked, until the mask widget is moved
/// inside `TxlemetryWidget` or removed. iOS and Android need no setup either
/// way.
class TxlemetryMaskWidget extends StatefulWidget {
  /// The widget subtree to mask in session replay snapshots.
  final Widget child;

  /// Creates a mask around [child] for session replay.
  const TxlemetryMaskWidget({super.key, required this.child});

  @override
  TxlemetryMaskWidgetState createState() => TxlemetryMaskWidgetState();
}

/// State for [TxlemetryMaskWidget].
@internal
class TxlemetryMaskWidgetState extends State<TxlemetryMaskWidget> {
  final GlobalKey _widgetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    notifyMaskWidgetMounted(context);
  }

  @override
  void dispose() {
    notifyMaskWidgetUnmounted(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(key: _widgetKey, child: widget.child);
  }
}
