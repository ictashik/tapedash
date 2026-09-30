import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/components/connection_layer.dart';
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
    this.initialCluster = 0,
    this.onClusterSettled,
  });

  /// The cluster the reel starts on: the one the user left it on last time.
  final int initialCluster;

  /// Called with the cluster the reel has come to rest on, after a swipe.
  final ValueChanged<int>? onClusterSettled;

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

  /// The window key the mounted slots were last built for.
  late int _windowAt = _windowKey(widget.initialCluster.toDouble());

  /// The raw drag position the spring chases, in clusters.
  late double _raw = widget.initialCluster.toDouble();

  /// The cluster last reported as settled on.
  late int _reported = widget.initialCluster;

  @override
  void initState() {
    super.initState();
    _reel = SpringValue(
      clock: widget.motion,
      spec: TapeSprings.page,
      initial: widget.initialCluster.toDouble(),
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

  /// Moves the reel to [cluster] (Garage's layout choice).
  void showCluster(int cluster) {
    _reel.setSpec(TapeSprings.page);
    _raw = cluster.toDouble();
    _reel.retarget(_raw.clamp(0.0, 4.0));
  }

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

  /// A cluster's slot is mounted while the reel is showing it or is between it and
  /// the next: the cluster below the position and the one above it (both, when it
  /// lies between two), and at rest that one alone. So a cluster swiped towards is
  /// there from the first pixel, and one the spring overshoots is not torn down.
  static bool _mounted(int i, double at) => i == at.floor() || i == at.ceil();

  /// What the mounted slots are built for: it changes when the reel leaves,
  /// reaches or crosses a cluster.
  static int _windowKey(double at) =>
      at.floor() * 2 + (at == at.floorToDouble() ? 0 : 1);

  void _onReel() {
    for (final f in _nearestFlags) {
      f.ping();
    }
    final key = _windowKey(_reel.value);
    if (key != _windowAt) {
      setState(() => _windowAt = key);
    }
    // At rest on a cluster: remember it (Garage's default layout follows).
    if (_reel.isSettled && _reel.value.round() != _reported) {
      _reported = _reel.value.round();
      widget.onClusterSettled?.call(_reported);
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
          child: _mounted(i, _reel.value)
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
            // Connection states (DESIGN.md 7.12): over whichever cluster
            // is showing, and nothing at all once connected.
            Positioned.fill(
              child: ConnectionLayer(
                presentation: widget.signals.linkPresentation,
                width: widget.width,
                height: widget.height,
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
