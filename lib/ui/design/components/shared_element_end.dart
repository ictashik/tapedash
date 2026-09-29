import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../motion/numeral_source.dart';
import '../motion/shared_elements.dart';
import 'numeral_format.dart';

/// Wraps a page's own copy of a shared-element readout, measuring its box
/// and registering the geometry with the [SharedElementsController] so the
/// strip's flight layer can paint the travelling copy.
///
/// The [child] is the page's own readout composition (the numeral, inside any
/// parked-scale wrapper the page applies). This widget does not change the
/// child visually; it only measures and registers.
class SharedElementEnd extends StatefulWidget {
  const SharedElementEnd({
    super.key,
    required this.id,
    required this.end,
    required this.page,
    required this.size,
    required this.source,
    required this.format,
    required this.typicalIntegerDigits,
    required this.role,
    this.parkedShare,
    this.parkedScaleShare = 1,
    this.staggerIndex = 0,
    this.active,
    required this.child,
  });

  /// The element id, e.g. [SharedElementIds.speed].
  final String id;

  final SharedElementEndKind end;
  final int page;

  /// The font size the readout is set at, for the flying copy.
  final double size;

  final NumeralSource source;
  final NumeralFormat format;
  final int typicalIntegerDigits;
  final NumeralRole role;

  /// The parked share the from end is under, so the flying copy matches its
  /// parked scale at the start of the flight.
  final ValueListenable<double>? parkedShare;
  final double parkedScaleShare;
  final int staggerIndex;

  /// While null, the end is always active; while not null, the registration
  /// only exists while [active] is true -- so the nearest cluster in a reel
  /// owns the registration.
  final ValueListenable<bool>? active;

  final Widget child;

  @override
  State<SharedElementEnd> createState() => _SharedElementEndState();
}

class _SharedElementEndState extends State<SharedElementEnd> {
  final GlobalKey _key = GlobalKey();
  SharedElementsController? _scope;
  bool _registered = false;
  bool _syncScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SharedElementsScope.maybeOf(context);
    if (!identical(next, _scope)) {
      // The scope was replaced (the strip rebuilt its controller): drop the
      // old registration without notifying anything from inside the build,
      // and re-register with the new one after the frame.
      _registered = false;
      _scope = next;
      _scheduleSync();
    }
  }

  @override
  void didUpdateWidget(SharedElementEnd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.end != widget.end ||
        oldWidget.page != widget.page ||
        oldWidget.size != widget.size ||
        !identical(oldWidget.source, widget.source) ||
        oldWidget.format != widget.format ||
        oldWidget.typicalIntegerDigits != widget.typicalIntegerDigits ||
        oldWidget.role != widget.role ||
        !identical(oldWidget.parkedShare, widget.parkedShare) ||
        oldWidget.parkedScaleShare != widget.parkedScaleShare ||
        oldWidget.staggerIndex != widget.staggerIndex) {
      _scheduleSync();
    }
    if (!identical(oldWidget.active, widget.active)) {
      oldWidget.active?.removeListener(_onActive);
      widget.active?.addListener(_onActive);
      _onActive();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.active?.addListener(_onActive);
  }

  @override
  void dispose() {
    widget.active?.removeListener(_onActive);
    _unregister();
    super.dispose();
  }

  void _onActive() {
    _scheduleSync();
  }

  /// Registration (and de-registration) happen after the current frame, not
  /// during it: the controller notifies the strip's flight layer, whose
  /// rebuild would otherwise be scheduled from inside the build phase
  /// (`didChangeDependencies` runs while the tree is building).
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _sync();
    });
  }

  void _sync() {
    final controller = _scope;
    if (controller == null) return;
    final active = widget.active;
    if (active != null && !active.value) {
      _unregister();
      return;
    }
    if (_registered) return;
    _registered = true;
    controller.registerEnd(
      widget.id,
      widget.end,
      page: widget.page,
      size: widget.size,
      source: widget.source,
      format: widget.format,
      typicalIntegerDigits: widget.typicalIntegerDigits,
      role: widget.role,
      parkedShare: widget.parkedShare,
      parkedScaleShare: widget.parkedScaleShare,
      staggerIndex: widget.staggerIndex,
    );
    _measure();
  }

  void _unregister() {
    if (!_registered) return;
    _registered = false;
    _scope?.unregisterEnd(widget.id, widget.end);
  }

  void _measure() {
    if (!mounted || !_registered) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    // The box's rect in page-local coordinates, by summing the layout
    // offsets of the render ancestors up to the Flow (the strip's page
    // painter). `localToGlobal` is not used: the Flow's paint transforms
    // are asymmetric in it (the walk from the page root does not include
    // the child's own slide), so a measured rect would drift with the
    // current offset. Layout offsets are stable.
    var current = box;
    var dx = 0.0;
    var dy = 0.0;
    while (current.parent is RenderBox && current.parent is! RenderFlow) {
      final parentData = current.parentData;
      if (parentData is BoxParentData) {
        dx += parentData.offset.dx;
        dy += parentData.offset.dy;
      }
      current = current.parent! as RenderBox;
    }
    if (current.parent is! RenderFlow) return;
    _scope?.updateEndRect(
      widget.id,
      widget.end,
      Rect.fromLTWH(dx, dy, box.size.width, box.size.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    // After every build (which may change the child), re-measure so the
    // registered rect is never stale.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
