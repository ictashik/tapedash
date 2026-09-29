import 'dart:async';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../location/location_source.dart';
import '../location/sim_location_source.dart';
import 'demo_drive.dart';

/// The demo's GPS (CLAUDE.md 7.5, 7.6): a simulated receiver that follows the
/// demo car along its route, so a demo trip has a route to show in Review and
/// History. The demo drive starts over now and then with a new car; this follows
/// whichever car is current, and is one stream to whoever listens.
class DemoLocationSource implements LocationSource {
  DemoLocationSource({
    required this.demo,
    required this.scheduler,
    required this.clock,
  }) {
    demo.cars.addListener(_rebind);
  }

  final DemoDrive demo;
  final Scheduler scheduler;
  final Clock clock;

  final StreamController<LocationFix> _fixes = StreamController.broadcast(
    sync: true,
  );
  SimLocationSource? _inner;
  // Cancelled in _release.
  // ignore: cancel_subscriptions
  StreamSubscription<LocationFix>? _sub;
  bool _wanted = false;

  @override
  Stream<LocationFix> get fixes => _fixes.stream;

  @override
  bool get isRunning => _wanted && _inner?.isRunning == true;

  @override
  Future<void> start() async {
    _wanted = true;
    _rebind();
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    await _release();
  }

  void _rebind() {
    unawaited(_release());
    final car = demo.cars.value;
    if (!_wanted || car == null) return;
    final inner = SimLocationSource(
      car: car,
      scheduler: scheduler,
      clock: clock,
    );
    _inner = inner;
    _sub = inner.fixes.listen(_fixes.add);
    inner.start();
  }

  /// Lets go of the current receiver. What it lets go of is taken before its
  /// first await, so a receiver made straight after (as [_rebind] does) is never
  /// the one that gets stopped.
  Future<void> _release() async {
    final sub = _sub;
    final inner = _inner;
    _sub = null;
    _inner = null;
    // Its timer is cancelled before anything is awaited, so that letting go is
    // complete as soon as this returns (a widget test checks for timers right
    // after the tree is disposed).
    final stopped = inner?.stop();
    await sub?.cancel();
    await stopped;
  }

  Future<void> dispose() async {
    demo.cars.removeListener(_rebind);
    await stop();
    await _fixes.close();
  }
}
