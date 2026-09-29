import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Fades a whole subtree in or out with a [ValueListenable] share, without
/// rebuilding it: the render object repaints from the listenable (DESIGN.md
/// 9.3). At 1 the child paints straight through with no layer; at 0 it is
/// skipped.
///
/// **A deliberate exception to "no Opacity" (CLAUDE.md 9):** in between, this
/// pushes one opacity layer. It is for transient reveals only (the ignition
/// sequence's flanks, DESIGN.md 7.13, 600 ms once per connection), never for
/// a value that moves for as long as the car is running.
class Presence extends SingleChildRenderObjectWidget {
  const Presence({super.key, required this.share, super.child});

  final ValueListenable<double> share;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPresence(share);

  @override
  void updateRenderObject(BuildContext context, RenderPresence renderObject) {
    renderObject.share = share;
  }
}

class RenderPresence extends RenderProxyBox {
  RenderPresence(this._share);

  ValueListenable<double> _share;

  set share(ValueListenable<double> value) {
    if (identical(_share, value)) return;
    if (attached) _share.removeListener(markNeedsPaint);
    _share = value;
    if (attached) _share.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _share.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _share.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final share = _share.value.clamp(0.0, 1.0);
    final child = this.child;
    if (child == null || share <= 0) return;
    if (share >= 1) {
      context.paintChild(child, offset);
      return;
    }
    // Compositing is only needed while it is between the two.
    layer = context.pushOpacity(
      offset,
      (share * 255).round(),
      super.paint,
      oldLayer: layer as OpacityLayer?,
    );
  }
}
