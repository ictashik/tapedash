import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/watch/page_ticks.dart';
import '../../design/components/watch/watch_face.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/motion_clock.dart';
import '../../design/motion/spring_value.dart';
import '../../design/motion/timeline.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/motion_tokens.dart';

/// The watch's reel of faces (DESIGN.md 16.5, 16.6): one face at a time filling the
/// circle, turned by the bezel, a vertical swipe or a tap.
///
/// - **Motion** reaches the first [motionFaces] only (Drive and Money). A swipe or
///   a turn towards a locked face gives a little and comes back, with the lock
///   glyph for [TapeMotion.lockGlyph]; a face left on when the car starts moving
///   returns to the nearest reachable one on `spring.snap`, inside the 300 ms the
///   motion return allows (DESIGN.md 7.2).
/// - **Parked** reaches all of them.
/// - A **tap** anywhere goes to the next face and, at the last, round to the
///   first. The bezel and the swipe stop at the ends.
///
/// The faces ride one `Flow`, so a move repaints transforms and never rebuilds a
/// face; the faces are mounted while on screen or between two.
class WatchReel extends StatefulWidget {
  const WatchReel({
    super.key,
    required this.faces,
    required this.mode,
    required this.motion,
    required this.face,
    this.rotary,
    this.motionFaces = 2,
    this.overlay,
    this.onSettled,
    this.onTapFace,
  });

  /// The faces, in reel order, the first at home.
  final List<Widget> faces;

  /// How many of them Motion can reach.
  final int motionFaces;

  final ValueListenable<DrivingMode> mode;
  final MotionClock motion;
  final WatchFace face;

  /// The bezel, one event a detent, +1 clockwise (a bigger number is a faster
  /// turn). Null for a watch with none.
  final Stream<int>? rotary;

  /// Drawn over the faces and under the page ticks (the connection states).
  final Widget? overlay;

  /// Called with the face the reel has come to rest on.
  final ValueChanged<int>? onSettled;

  /// Called with the face a tap landed on; returning true says the face took the
  /// tap itself (the menu cover opens the menu) and the reel stays put. Null, or
  /// false, goes to the next face.
  final bool Function(int face)? onTapFace;

  @override
  State<WatchReel> createState() => WatchReelState();

  /// The reachable range for [mode], inclusive.
  static (int, int) reachOf(DrivingMode mode, int count, int motionFaces) =>
      switch (mode) {
        DrivingMode.parked => (0, count - 1),
        DrivingMode.motion => (0, (motionFaces - 1).clamp(0, count - 1)),
      };

  /// The position a drag wants, resisted past the reachable range: it gives
  /// [TapeMotion.lockedSwipeGive] of a face and holds (DESIGN.md 7.1's
  /// rubber-band).
  static double resisted(double raw, double min, double max) {
    if (raw < min) {
      return min - TapeMotion.lockedSwipeGive * (min - raw).clamp(0.0, 1.0);
    }
    if (raw > max) {
      return max + TapeMotion.lockedSwipeGive * (raw - max).clamp(0.0, 1.0);
    }
    return raw;
  }
}

class WatchReelState extends State<WatchReel> {
  late SpringValue _pos;
  late final ValueNotifier<int> _reach;
  Timeline? _lockGlyph;
  StreamSubscription<int>? _bezel;
  double _raw = 0;
  int _windowAt = 0;
  int _reported = 0;

  /// How many faces can be reached now.
  ValueListenable<int> get reachable => _reach;

  /// Where the reel is, in faces, for the page ticks.
  ValueListenable<double> get position => _pos;

  @override
  void initState() {
    super.initState();
    _pos = SpringValue(clock: widget.motion, spec: TapeSprings.page, initial: 0)
      ..addListener(_onPosition);
    _reach = ValueNotifier(_count(widget.mode.value));
    widget.mode.addListener(_onMode);
    _listen();
  }

  @override
  void didUpdateWidget(WatchReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.mode, widget.mode)) {
      oldWidget.mode.removeListener(_onMode);
      widget.mode.addListener(_onMode);
      _onMode();
    }
    if (!identical(oldWidget.rotary, widget.rotary)) _listen();
  }

  @override
  void dispose() {
    widget.mode.removeListener(_onMode);
    _bezel?.cancel();
    _lockGlyph?.dispose();
    _pos
      ..removeListener(_onPosition)
      ..dispose();
    _reach.dispose();
    super.dispose();
  }

  void _listen() {
    _bezel?.cancel();
    _bezel = widget.rotary?.listen(_onBezel);
  }

  int _count(DrivingMode mode) {
    final (_, max) = WatchReel.reachOf(
      mode,
      widget.faces.length,
      widget.motionFaces,
    );
    return max + 1;
  }

  (int, int) get _range => WatchReel.reachOf(
    widget.mode.value,
    widget.faces.length,
    widget.motionFaces,
  );

  /// The face the reel is nearest to.
  int get current => _pos.value.round();

  /// Where the reel is, for a test.
  double get debugPosition => _pos.value;

  /// Moves to [face], within what the lock allows.
  void goTo(int face) {
    final (min, max) = _range;
    _pos
      ..setSpec(TapeSprings.page)
      ..retarget(face.clamp(min, max).toDouble());
  }

  /// The next face, and round to the first from the last (a tap).
  void next() {
    final (min, max) = _range;
    final at = current;
    goTo(at >= max ? min : at + 1);
  }

  void _onBezel(int detents) {
    final (min, max) = _range;
    final wanted = current + (detents > 0 ? 1 : -1);
    if (wanted > max && widget.mode.value == DrivingMode.motion) {
      _showLockGlyph();
    }
    goTo(wanted.clamp(min, max));
  }

  void _onMode() {
    _reach.value = _count(widget.mode.value);
    final (min, max) = _range;
    if (_pos.value > max || _pos.value < min) {
      _pos
        ..setSpec(TapeSprings.snap)
        ..retarget(_pos.value.clamp(min.toDouble(), max.toDouble()));
    }
    setState(() {});
  }

  void _onPosition() {
    final key = _windowKey(_pos.value);
    if (key != _windowAt) setState(() => _windowAt = key);
    if (_pos.isSettled && _pos.value.round() != _reported) {
      _reported = _pos.value.round();
      widget.onSettled?.call(_reported);
    }
  }

  static int _windowKey(double at) =>
      at.floor() * 2 + (at == at.floorToDouble() ? 0 : 1);

  static bool _mounted(int i, double at) => i == at.floor() || i == at.ceil();

  void _onDragStart(DragStartDetails details) {
    _pos.setSpec(TapeSprings.page);
    _raw = _pos.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final (min, max) = _range;
    // Dragging up moves the reel on, as a list does.
    _raw -= details.primaryDelta! / widget.face.diameter;
    _pos.retarget(WatchReel.resisted(_raw, min.toDouble(), max.toDouble()));
  }

  void _onDragEnd(DragEndDetails details) => _settle(
    _raw,
    -details.velocity.pixelsPerSecond.dy / widget.face.diameter,
  );

  void _settle(double at, double velocity) {
    final (min, max) = _range;
    var landing = at.round();
    if (velocity.abs() > TapeMotion.pageFlingVelocity) {
      landing += velocity > 0 ? 1 : -1;
    }
    final clamped = landing.clamp(min, max);
    if (clamped != landing && widget.mode.value == DrivingMode.motion) {
      _showLockGlyph();
    }
    _pos.retarget(clamped.toDouble());
  }

  void _showLockGlyph() {
    _lockGlyph?.dispose();
    _lockGlyph = Timeline(
      clock: widget.motion,
      length: TapeMotion.lockGlyph,
      onDone: () {
        if (mounted) setState(() => _lockGlyph = null);
      },
    )..start();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.face;
    final palette = TapeTheme.of(context).palette;
    return SizedBox.square(
      dimension: face.diameter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () => _settle(_pos.value, 0),
        onTap: () {
          if (widget.onTapFace?.call(current) ?? false) return;
          next();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Flow(
                delegate: _ReelFlow(position: _pos, extent: face.diameter),
                children: [
                  for (var i = 0; i < widget.faces.length; i++)
                    SizedBox.square(
                      dimension: face.diameter,
                      child: _mounted(i, _pos.value)
                          ? widget.faces[i]
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            if (widget.overlay != null) Positioned.fill(child: widget.overlay!),
            Positioned(
              top: face.tapeY - 1.5,
              left: 0,
              right: 0,
              child: Center(
                child: PageTicks(position: _pos, count: _reach),
              ),
            ),
            if (_lockGlyph != null)
              Positioned(
                top: face.footY - 8,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _lockGlyph!,
                    builder: (context, _) {
                      final t = _lockGlyph!.progress;
                      final alpha = t < 0.75 ? 1.0 : 1.0 - (t - 0.75) / 0.25;
                      return TapeIconView(
                        TapeIcon.lock,
                        size: 16,
                        color: palette.inkMid.withValues(
                          alpha: palette.inkMid.a * alpha.clamp(0.0, 1.0),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReelFlow extends FlowDelegate {
  _ReelFlow({required this.position, required this.extent})
    : super(repaint: position);

  final ValueListenable<double> position;
  final double extent;

  @override
  void paintChildren(FlowPaintingContext context) {
    final at = position.value;
    for (var i = 0; i < context.childCount; i++) {
      final dy = (i - at) * extent;
      if (dy < context.size.height && dy + extent > 0) {
        context.paintChild(i, transform: Matrix4.translationValues(0, dy, 0));
      }
    }
  }

  @override
  bool shouldRepaint(_ReelFlow old) => old.extent != extent;
}
