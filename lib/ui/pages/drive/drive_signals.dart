import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../core/observable.dart';
import '../../../core/scheduler.dart';
import '../../../obd/obd_session.dart' show ConnectionStatus;
import '../../../vehicle/reading.dart';
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
       load = SmoothedSignal(
         motion: motion,
         clock: clock,
         spring: TapeSprings.needle,
       ),
       voltage = SmoothedSignal(
         motion: motion,
         clock: clock,
         spring: TapeSprings.needle,
       ),
       throttle = SmoothedSignal(
         motion: motion,
         clock: clock,
         spring: TapeSprings.needle,
       ),
       longitudinalAcceleration = SmoothedSignal(
         motion: motion,
         clock: clock,
         spring: TapeSprings.needle,
       ),
       lateralAcceleration = SmoothedSignal(
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
    load.bind(vehicle.load);
    voltage.bind(vehicle.voltage);
    vehicle.motion.addListener(_onMotion);
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

  /// Calculated engine load %, and the module voltage V. Real sensors
  /// (`VehicleState.load`/`.voltage`, the poller's medium and slow tiers),
  /// bound like the four above; the Telemetry cluster's grid is the first
  /// reader, which is why they arrive now and not with the earlier
  /// clusters.
  final SmoothedSignal load;
  final SmoothedSignal voltage;

  /// m/s^2, from `VehicleState.motion` (itself from the change in smoothed
  /// OBD speed, CLAUDE.md 8.8) -- the road view's body pitch (DESIGN.md
  /// 6.11). Not a plain `.bind()`: `MotionSample` is not a `Reading`, so
  /// each sample is converted and ingested by hand.
  final SmoothedSignal longitudinalAcceleration;

  /// m/s^2, positive to the right -- the road view's body roll (DESIGN.md
  /// 6.11). DESIGN.md asks for the accelerometer, low-pass filtered; that
  /// pipeline (a `DeviceFeatures.acceleration` stream, filtered) does not
  /// exist yet, so this is never ingested into. `RoadView` already reads a
  /// valueless signal as 0 (flat, no roll) rather than needing a real
  /// source to render at all, so the car simply does not roll yet, an
  /// honest gap rather than an invented reading.
  final SmoothedSignal lateralAcceleration;

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

  void _onMotion() {
    final sample = vehicle.motion.value;
    if (sample == null) return;
    longitudinalAcceleration.ingest(
      Reading(
        value: sample.accelerationMs2,
        at: sample.at,
        receivedAt: sample.receivedAt,
      ),
    );
  }

  static AdapterLinkState _adapterStateFor(ConnectionStatus status) =>
      switch (status) {
        ConnectionStatus.connected ||
        ConnectionStatus.waitingForIgnition => AdapterLinkState.flowing,
        ConnectionStatus.stopped ||
        ConnectionStatus.searching => AdapterLinkState.searching,
        ConnectionStatus.lost => AdapterLinkState.lost,
      };

  void dispose() {
    vehicle.motion.removeListener(_onMotion);
    wallClock.dispose();
    rpm.dispose();
    speed.dispose();
    coolant.dispose();
    throttle.dispose();
    load.dispose();
    voltage.dispose();
    longitudinalAcceleration.dispose();
    lateralAcceleration.dispose();
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
