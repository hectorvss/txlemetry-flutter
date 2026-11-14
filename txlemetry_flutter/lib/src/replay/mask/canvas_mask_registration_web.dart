import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../util/logging.dart';
import '../web/web_canvas_mask_provider.dart';
import 'txlemetry_mask_controller.dart';

/// A mounted `TxlemetryMaskWidget` or `TxlemetryUnmaskWidget` requests masking, so it
/// opts the app into canvas masking even when `txlemetry.init` never declared
/// `maskRegionsFn`.
///
/// Deferred to the end of the frame because `initState` runs during Flutter's
/// build phase: registering calls straight into txlemetry-js and restarts an
/// in-flight recording.
void notifyMaskWidgetMounted(BuildContext context) {
  WebCanvasMaskProvider.registerMaskWidgetContext(context);
  SchedulerBinding.instance.addPostFrameCallback((_) {
    try {
      if (!_isInTrackedTree(context)) {
        printIfDebug(
          'Txlemetry: this mask/unmask widget is outside the TxlemetryWidget tree '
          'Txlemetry tracks, so masking could never cover it — it does not '
          'enable web canvas masking.',
        );
        return;
      }
      WebCanvasMaskProvider.notifyMaskWidgetMounted();
    } catch (e) {
      printIfDebug('Txlemetry: error enabling web canvas masking: $e');
    }
  });
}

void notifyMaskWidgetUnmounted(BuildContext context) {
  WebCanvasMaskProvider.unregisterMaskWidgetContext(context);
}

/// The masking walk only sees the tracked tree (whose route-dependent root is
/// [WebCanvasMaskProvider.trackedTreeRoot], the boundary this check walks
/// against), so a mask widget outside it would opt masking in while its own
/// rects are never produced — the walk would succeed and ship rects that do
/// not cover the widget. With
/// no tracked tree at all the opt-in stays allowed: every walk then fails and
/// frames are skipped (fail closed), which is the documented behavior for an
/// app missing TxlemetryWidget.
///
/// The check runs once, in the mount's post-frame callback: a null tracked
/// context at that moment is treated as the no-TxlemetryWidget shape and
/// allowed. That one-shot allowance is backstopped by
/// [WebCanvasMaskProvider], which revalidates every mounted mask widget when
/// regions are computed — if a TxlemetryWidget later mounts without containing
/// this widget, frames are skipped (fail closed) rather than recorded
/// unmasked.
bool _isInTrackedTree(BuildContext context) {
  final trackedContext =
      TxlemetryMaskController.instance.containerKey.currentContext;
  if (trackedContext == null) {
    return true;
  }
  final tracked = WebCanvasMaskProvider.trackedTreeRoot(trackedContext);
  if (tracked == null) {
    // cannot prove the mask widget is outside the tracked tree
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final renderObject = context.findRenderObject();
  if (renderObject == null) {
    return false;
  }
  RenderObject? node = renderObject;
  while (node != null) {
    if (identical(node, tracked)) {
      return true;
    }
    node = node.parent;
  }
  return false;
}
