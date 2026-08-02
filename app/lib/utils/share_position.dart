import 'package:flutter/widgets.dart';

/// Computes a `sharePositionOrigin` rect that iOS will accept.
///
/// iPad — and, on some iOS versions, iPhone — require the share sheet's
/// `sharePositionOrigin` to be a **non-zero** rectangle that lies **within**
/// the source view (the app window). Passing a widget's raw render box can
/// violate that when the widget overflows the viewport: the platform channel
/// then throws
/// `sharePositionOrigin: argument must be set … must be non-zero and within
/// coordinate space of source view`.
///
/// This clamps the render box to the window bounds and, if that leaves nothing
/// usable (detached box, no overlap, no MediaQuery), falls back to a small rect
/// at the centre of the window. Returns `null` only when there is no window to
/// anchor to, which is the correct value to pass on platforms that ignore it.
Rect? sharePositionOriginFor(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  final window = media == null ? null : Offset.zero & media.size;

  final object = context.findRenderObject();
  if (object is RenderBox && object.attached && object.hasSize) {
    final rect = object.localToGlobal(Offset.zero) & object.size;
    final clamped = window == null ? rect : rect.intersect(window);
    if (clamped.width > 0 && clamped.height > 0) return clamped;
  }

  if (window != null && window.width > 0 && window.height > 0) {
    return Rect.fromCenter(center: window.center, width: 1, height: 1);
  }
  return null;
}
