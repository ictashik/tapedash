import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../core/observable.dart';
import '../../../core/scheduler.dart';
import '../../../obd/obd_session.dart' show ConnectionStatus;
import '../../../vehicle/vehicle_state.dart';
import '../../design/components/status_strip.dart' show AdapterLinkState;
import '../../design/motion/motion_clock.dart';
import '../../design/motion/observable_listenable.dart';
import '../../design/motion/smoothing_pipeline.dart';
import '../../design/motion/wall_clock.dart';
import '../../design/tokens/motion_tokens.dart';

/// The live `SmoothedSignal`s a Drive cluster reads, bound once to a
/// [VehicleState] and shared across whichever cluster layout is on screen,
/// so switching clusters (a later phase 3b piece, DESIGN.md 7.1's vertical
/// swipe) does not mean losing a spring's own momentum or re-binding.
///
/// This is the whole of `SmoothedSignal.bind` in practice (CLAUDE.md 6,
/// DESIGN.md 5.2 steps 3-5): each field is a spring already following a
/// [VehicleState] sensor, ready for a component to read directly. Nothing
/// here invents data -- a cluster leaves a slot empty rather than show a
/// value with no real source (CLAUDE.md 1's "honest numbers"). Money,
/// instant km/L, the eco bar and trip distance/time all need `fuel/`,
/// `money/` or `trips/`, none of which exist before phase 4, so no signal
/// for them is built here yet; a cluster composing from this class simply
/// omits the DESIGN.md 7.3 slots that would show them, documented at each
/// call site, not silently.
class DriveSignals {
  DriveSignals({
    required this.vehicle,
    required MotionClock motion,
    required this.clock,
    required Scheduler scheduler,
    required Observable<ConnectionStatus> connection,
  }) : wallClock = WallClockTicker(clock: clock, scheduler: scheduler),
       rpm = SmoothedSignal(
         motion: motion,
         clock: clock,
         spring: TapeSprings.needle,
       ),
       speed = SmoothedSignal(
         motion: motion,
         clock: clock,
         spring: TapeSprings.gauge,
       ),
       coolant = SmoothedSignal(
         motion: motion,
         clock: clock,
         spring: TapeSprings.needle,
       ),
       throttle = SmoothedSignal(
         motion: motion,
         clock: clock,
         spring: TapeSprings.needle,
       ),
       _mode = ObservableListenable(vehicle.mode),
       _connection = ObservableListenable(connection) {
    rpm.bind(vehicle.rpm);
    speed.bind(vehicle.speed);
    coolant.bind(vehicle.coolant);
    throttle.bind(vehicle.throttle);
    _adapter = _MappedListenable(_connection, _adapterStateFor);
  }

  final VehicleState vehicle;
  final Clock clock;

  /// The status strip's clock (DESIGN.md 6.9), ticking on the same injected
  /// [Clock] and [Scheduler] as everything else, not `DateTime.now()`.
  final WallClockTicker wallClock;

  final SmoothedSignal rpm;
  final SmoothedSignal speed;
  final SmoothedSignal coolant;
  final SmoothedSignal throttle;

  final ObservableListenable<DrivingMode> _mode;
  final ObservableListenable<ConnectionStatus> _connection;
  late final _MappedListenable<ConnectionStatus, AdapterLinkState> _adapter;

  /// Motion or parked (DESIGN.md 7.2), straight from `VehicleState.mode`.
  ValueListenable<DrivingMode> get mode => _mode;

  /// The status strip's own small vocabulary (DESIGN.md 6.9), mapped from
  /// the session's real ConnectionStatus (DESIGN.md 7.12's full states are
  /// a separate, later piece of phase 3b; this is only the adapter glyph).
  ValueListenable<AdapterLinkState> get adapter => _adapter;

  /// The raw connection status, for chrome that needs more than the
  /// adapter glyph's three states (DESIGN.md 7.12, not yet built).
  ValueListenable<ConnectionStatus> get connection => _connection;

  /// GPS has no real source yet: the native channel is phase 4 (CLAUDE.md
  /// 13), not phase 3b. A plain "no fix" rather than inventing one.
  final ValueListenable<bool> gpsHasFix = ValueNotifier(false);

  /// Likewise: phone-temperature polling (CLAUDE.md 9) is cross-cutting app
  /// shell work, not yet wired to any page. A plain "not hot" rather than
  /// inventing one.
  final ValueListenable<bool> phoneHot = ValueNotifier(false);

  static AdapterLinkState _adapterStateFor(ConnectionStatus status) =>
      switch (status) {
        ConnectionStatus.connected ||
        ConnectionStatus.waitingForIgnition => AdapterLinkState.flowing,
        ConnectionStatus.stopped ||
        ConnectionStatus.searching => AdapterLinkState.searching,
        ConnectionStatus.lost => AdapterLinkState.lost,
      };

  void dispose() {
    wallClock.dispose();
    rpm.dispose();
    speed.dispose();
    coolant.dispose();
    throttle.dispose();
    _mode.dispose();
    _adapter.dispose();
    _connection.dispose();
  }
}

/// A [ValueListenable] that reads [source] through [map] -- so the status
/// strip's own `AdapterLinkState` never has to know `ConnectionStatus`
/// exists (`ui/design/` components take plain values, never a service's
/// own types, the same reasoning `AdapterLinkState`'s own doc comment
/// gives). Does not own [source]; the caller disposes that separately.
class _MappedListenable<S, T> extends ChangeNotifier
    implements ValueListenable<T> {
  _MappedListenable(this._source, this._map) {
    _source.addListener(_onSource);
  }

  final ValueListenable<S> _source;
  final T Function(S) _map;

  @override
  T get value => _map(_source.value);

  void _onSource() => notifyListeners();

  @override
  void dispose() {
    _source.removeListener(_onSource);
    super.dispose();
  }
}
