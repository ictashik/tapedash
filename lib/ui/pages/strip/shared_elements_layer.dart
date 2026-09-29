import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../design/components/centered_numeral.dart';
import '../../design/components/parked_scale.dart';
import '../../design/motion/shared_elements.dart';

/// The flight layer (DESIGN.md 7.1): paints each shared element's travelling
/// copy as the strip's offset moves between its two pages. The element's
/// position, size and the fade of each page's own copy are pure functions of
/// the offset spring, so every flight is interruptible and reversible
/// mid-swipe.
class SharedElementsLayer extends StatefulWidget {
  const SharedElementsLayer({
    super.key,
    required this.controller,
    required this.offset,
  });

  final SharedElementsController controller;
  final ValueListenable<double> offset;

  @override
  State<SharedElementsLayer> createState() => _SharedElementsLayerState();
}

class _SharedElementsLayerState extends State<SharedElementsLayer> {
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(SharedElementsLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  /// The controller notifies from anywhere in the frame -- including, via a
  /// wrapper's `dispose`, while the tree is finalizing, where a direct
  /// `setState` is illegal. The rebuild is therefore always deferred to the
  /// end of the frame: registration changes are rare (mounts, unmounts,
  /// cluster switches), so a one-frame defer is invisible.
  void _onController() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final specs = widget.controller.elements.toList();
    return Stack(
      children: [
        for (final spec in specs)
          _ElementFlight(
            offset: widget.offset,
            spec: spec,
            child: CenteredNumeral(
              source: spec.source,
              format: spec.format,
              typicalIntegerDigits: spec.typicalIntegerDigits,
              size: spec.fromSize,
              role: spec.role,
            ),
          ),
      ],
    );
  }
}

/// One flying numeral, whose transform is recomputed from the offset spring
/// every frame without rebuilding.
class _ElementFlight extends SingleChildRenderObjectWidget {
  const _ElementFlight({super.child, required this.offset, required this.spec});

  final ValueListenable<double> offset;
  final SharedElementSpec spec;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderElementFlight(offset: offset, spec: spec);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderElementFlight renderObject,
  ) => renderObject.replace(offset, spec);
}

class _RenderElementFlight extends RenderProxyBox {
  _RenderElementFlight({required this.offset, required this.spec});

  ValueListenable<double> offset;
  SharedElementSpec spec;

  /// Swaps the listenables, re-pointing the paint listeners: the layer
  /// rebuilds on registration changes, and the offset spring is replaced by
  /// the strip when the motion clock changes.
  void replace(ValueListenable<double> newOffset, SharedElementSpec newSpec) {
    if (!identical(offset, newOffset)) {
      offset.removeListener(markNeedsPaint);
      offset = newOffset;
      offset.addListener(markNeedsPaint);
    }
    if (!identical(spec, newSpec)) {
      spec.parkedShare?.removeListener(markNeedsPaint);
      spec = newSpec;
      spec.parkedShare?.addListener(markNeedsPaint);
    }
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    offset.addListener(markNeedsPaint);
    spec.parkedShare?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    offset.removeListener(markNeedsPaint);
    spec.parkedShare?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    offset.removeListener(markNeedsPaint);
    spec.parkedShare?.removeListener(markNeedsPaint);
    super.dispose();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(constraints.loosen(), parentUsesSize: false);
    }
    size = constraints.smallest;
  }

  @override
  void paint(PaintingContext context, Offset paintOffset) {
    final child = this.child;
    if (child == null) return;
    final o = offset.value;
    final t = SharedElementsController.flightOf(
      o,
      fromPage: spec.fromPage,
      toPage: spec.toPage,
    );
    if (t <= 0 || t >= 1) return;

    final fromScale = spec.parkedShare == null
        ? 1.0
        : ParkedScale.scaleFor(
            parkedShare: spec.parkedShare!.value,
            parkedScaleShare: spec.parkedScaleShare,
            staggerIndex: spec.staggerIndex,
          );
    final s = SharedElementsController.scaleAt(
      t,
      fromScale,
      spec.toSize / spec.fromSize,
    );
    if (s <= 0) return;

    // The registered rects are in page-local coordinates, which is this
    // layer's own space (a page fills the viewport exactly), so they are
    // used directly: no origin conversion, and nothing depends on where the
    // strip sits on screen.
    final rect = SharedElementsController.rectAt(t, spec.fromRect, spec.toRect);

    // The child is laid out at this box's own origin, so the scale pivots
    // on the child's own centre, not on the from rect's. The transform goes
    // through `pushTransform`, not the canvas: the numeral is a repaint
    // boundary, and canvas transforms do not propagate into repaint-
    // boundary children.
    final childCenter = child.size.center(Offset.zero);
    final transform = Matrix4.identity()
      ..translateByDouble(rect.center.dx, rect.center.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-childCenter.dx, -childCenter.dy, 0, 1);
    context.pushTransform(
      true,
      Offset.zero,
      transform,
      (ctx, childOffset) => ctx.paintChild(child, childOffset),
    );
  }
}
