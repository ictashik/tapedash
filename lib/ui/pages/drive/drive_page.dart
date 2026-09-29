import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/motion/motion_clock.dart';
import '../../design/motion/spring_value.dart';
import '../../design/tokens/motion_tokens.dart';
import 'apex_cluster.dart';
import 'drive_signals.dart';
import 'minimal_cluster.dart';
import 'road_cluster.dart';
import 'tape_cluster.dart';
import 'telemetry_cluster.dart';

/// The Drive page (DESIGN.md 7.3): the five cluster layouts, cycled by a
/// vertical swipe with a reel-like transition, the choice held for the
/// session. The clusters are already built; this page is their one mount,
/// so a horizontal page move never tears a cluster down (DriveSignals' own
/// philosophy: bind once, share across layouts).
///
/// A reel has no lock of its own: a cluster switch is safe anywhere, so the
/// vertical swipe is the same chase-and-settle pattern the strip uses
/// horizontally, on `spring.page`, with the hand's own velocity at the
/// release. The cluster layouts, in the order DESIGN.md 7.3 names them:
/// Apex (default), Tape, Minimal, Telemetry, Road. The reel cycles forward
/// and wraps at the ends, because a reel is a loop, not a list.
class DrivePage extends StatefulWidget {
  const DrivePage({
    super.key,
    required this.signals,
    required this.motion,
    required this.width,
    required this.height,
  });

  final DriveSignals signals;

  /// The clock the reel's own motion runs on.
  final MotionClock motion;

  final double width;
  final double height;

  @override
  State<DrivePage> createState() => DrivePageState();
}

class DrivePageState extends State<DrivePage> {
  late SpringValue _reel;
  late final List<_NearestFlag> _nearestFlags;
  late final List<Widget> _clusters;

  /// The cluster index the mounted slots were last built around.
  int _windowAt = 0;

  /// The raw drag position the spring chases, in clusters.
  double _raw = 0;

  @override
  void initState() {
    super.initState();
    _reel = SpringValue(
      clock: widget.motion,
      spec: TapeSprings.page,
      initial: 0,
    )..addListener(_onReel);
    _nearestFlags = List.generate(5, (i) => _NearestFlag(this, i));
    _clusters = _buildClusters();
  }

  @override
  void didUpdateWidget(DrivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.motion, widget.motion)) {
      final at = _reel.value;
      _reel.dispose();
      _reel = SpringValue(
        clock: widget.motion,
        spec: TapeSprings.page,
        initial: at,
      )..addListener(_onReel);
    }
  }

  @override
  void dispose() {
    for (final f in _nearestFlags) {
      f.dispose();
    }
    _reel.removeListener(_onReel);
    _reel.dispose();
    super.dispose();
  }

  /// Where the reel is now, in clusters.
  double get reel => _reel.value;

  /// The five clusters, in the order DESIGN.md 7.3 names them, built once.
  List<Widget> _buildClusters() => [
    ApexCluster(
      signals: widget.signals,
      width: widget.width,
      height: widget.height,
      heroSlotActive: _nearestFlags[0],
    ),
    TapeCluster(
      signals: widget.signals,
      width: widget.width,
      height: widget.height,
    ),
    MinimalCluster(
      signals: widget.signals,
      width: widget.width,
      height: widget.height,
      heroSlotActive: _nearestFlags[2],
    ),
    TelemetryCluster(
      signals: widget.signals,
      width: widget.width,
      height: widget.height,
    ),
    RoadCluster(
      signals: widget.signals,
      width: widget.width,
      height: widget.height,
    ),
  ];

  /// A cluster's slot is mounted while the reel could be showing it or a
  /// neighbour: within a cluster of the position.
  static bool _mounted(int i, double at) => i - 1 < at && at < i + 1;

  void _onReel() {
    for (final f in _nearestFlags) {
      f.ping();
    }
    final floor = _reel.value.floor();
    if (floor != _windowAt) {
      setState(() => _windowAt = floor);
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _reel.setSpec(TapeSprings.page);
    _raw = _reel.value;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // The reel moves against the hand's own dy: a downward hand (dy
    // negative) advances the reel, up through the list.
    _raw -= details.primaryDelta! / widget.height;
    _reel.retarget(_raw.clamp(0.0, 4.0));
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    // The hand's own velocity, in the reel's own direction: a downward hand
    // (dy negative) moves the reel forward, up through the list.
    _settle(_raw, -details.velocity.pixelsPerSecond.dy / widget.height);
  }

  void _onVerticalDragCancel() {
    _settle(_reel.value, 0);
  }

  void _settle(double at, double velocity) {
    // The hand's own momentum carries the landing a quarter page further in
    // the hand's own direction: a fling from a settled cluster goes to the
    // next one, and one already past the quarter-way goes no further than
    // the cluster it was already heading into.
    final landing = velocity.abs() > TapeMotion.pageFlingVelocity
        ? (velocity > 0 ? at + 0.25 : at - 0.25).round().clamp(0, 4)
        : at.round().clamp(0, 4);
    _reel.retarget(landing.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (var i = 0; i < _clusters.length; i++)
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: _mounted(i, _reel.value.floorToDouble())
              ? _clusters[i]
              : const SizedBox.shrink(),
        ),
    ];

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        onVerticalDragCancel: _onVerticalDragCancel,
        child: Stack(
          children: [
            Positioned.fill(
              child: Flow(
                delegate: _ReelFlowDelegate(reel: _reel, height: widget.height),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reel's own motion (DESIGN.md 7.3): the clusters ride one [Flow]
/// vertically, and a cluster that is off screen is not painted at all.
class _ReelFlowDelegate extends FlowDelegate {
  _ReelFlowDelegate({required this.reel, required this.height})
    : super(repaint: reel);

  final ValueListenable<double> reel;
  final double height;

  @override
  void paintChildren(FlowPaintingContext context) {
    final at = reel.value;
    for (var i = 0; i < context.childCount; i++) {
      final dy = (i - at) * height;
      if (dy < context.size.height && dy + height > 0) {
        context.paintChild(i, transform: Matrix4.translationValues(0, dy, 0));
      }
    }
  }

  @override
  bool shouldRepaint(_ReelFlowDelegate oldDelegate) =>
      oldDelegate.height != height;
}

/// A [ValueListenable<bool>] that is true when the nearest cluster (the one
/// the reel is settled on or nearest to) is [index]. The [DrivePageState]
/// pings all flags each frame the reel moves; the flag reads the state's
/// current [reel] value and notifies only when the nearest cluster changes.
class _NearestFlag extends ChangeNotifier implements ValueListenable<bool> {
  _NearestFlag(this._state, this._index);

  final DrivePageState _state;
  final int _index;
  int _last = -1;

  @override
  bool get value => _index == _state.reel.round();

  void ping() {
    final v = _state.reel.round();
    if (v != _last) {
      _last = v;
      notifyListeners();
    }
  }
}
