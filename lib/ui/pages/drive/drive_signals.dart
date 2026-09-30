import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../core/observable.dart';
import '../../../core/scheduler.dart';
import '../../../obd/obd_session.dart' show ConnectionStatus;
import '../../../vehicle/reading.dart';
import '../../../vehicle/vehicle_state.dart';
import '../../design/components/status_strip.dart' show AdapterLinkState;
import '../../design/motion/connection_presentation.dart';
import '../../design/motion/ignition_sequence.dart';
import '../../design/motion/motion_clock.dart';
import '../../design/motion/observable_listenable.dart';
import '../../design/motion/parked_share.dart';
import '../../design/motion/smoothing_pipeline.dart';
import '../../design/motion/wall_clock.dart';
import '../../design/tokens/motion_tokens.dart';
import '../money/money_figure.dart' show MappedShare;
import '../money/money_signals.dart';

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
    IgnitionMode ignitionMode = IgnitionMode.full,
    bool reduceMotion = false,
    this.demoMode = false,
    this.money,
    ValueListenable<bool>? gpsHasFix,
    ValueListenable<bool>? phoneHot,
  }) : gpsHasFix = gpsHasFix ?? ValueNotifier(false),
       phoneHot = phoneHot ?? ValueNotifier(false),
       wallClock = WallClockTicker(clock: clock, scheduler: scheduler),
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
    _parkedFlag = _MappedListenable<DrivingMode, bool>(
      _mode,
      (m) => m == DrivingMode.parked,
    );
    parkedShare = ParkedShare(
      source: _parkedFlag,
      clock: motion,
      initiallyParked: _mode.value == DrivingMode.parked,
    );
    _adapter = _MappedListenable(_connection, _adapterStateFor);
    ignition = IgnitionSequence(
      clock: motion,
      rpm: rpm,
      speed: speed,
      mode: ignitionMode,
      reduceMotion: reduceMotion,
    );
    vehicle.rpm.addListener(_maybeIgnite);
    _connection.addListener(_maybeIgnite);
    linkPresentation = ConnectionPresentation(
      clock: motion,
      initial: _phaseFor(_connection.value),
    );
    _connection.addListener(_onConnection);
    _maybeIgnite();
  }

  /// The connection states' shares (DESIGN.md 7.12), read by the page's
  /// [ConnectionLayer].
  late final ConnectionPresentation linkPresentation;

  void _onConnection() => linkPresentation.update(_phaseFor(_connection.value));

  static LinkPhase _phaseFor(ConnectionStatus status) => switch (status) {
    ConnectionStatus.stopped ||
    ConnectionStatus.searching => LinkPhase.searching,
    ConnectionStatus.waitingForIgnition => LinkPhase.waitingForIgnition,
    ConnectionStatus.connected => LinkPhase.connected,
    ConnectionStatus.lost => LinkPhase.lost,
  };

  /// The ignition sequence (DESIGN.md 7.13): plays once per connection, on
  /// the first valid rpm above 400 while connected. The clusters read its
  /// shares (the arc's wave, the horizon's draw, the flanks' fade); the
  /// needle and numerals it moves are this class's own signals, so every
  /// cluster gets those without asking.
  late final IgnitionSequence ignition;

  /// The sequence's shares, as plain listenables for the components
  /// (step 1's arc wave, step 4's horizon draw and the flank away from the driver; the driver-side flank has nothing to show until phase 4).
  late final IgnitionShare arcWave = IgnitionShare(ignition, (i) => i.arcWave);
  late final IgnitionShare horizonDraw = IgnitionShare(
    ignition,
    (i) => i.horizonDraw,
  );
  late final IgnitionShare flankAway = IgnitionShare(
    ignition,
    (i) => i.flank(0),
  );

  /// The flank nearer the driver, which fades in second (DESIGN.md 7.13's stagger).
  late final IgnitionShare flankDriver = IgnitionShare(
    ignition,
    (i) => i.flank(1),
  );

  /// The first rpm that counts as the engine running (CLAUDE.md 8.6).
  static const double ignitionRpm = 400;

  void _maybeIgnite() {
    switch (_connection.value) {
      case ConnectionStatus.stopped ||
          ConnectionStatus.searching ||
          ConnectionStatus.waitingForIgnition:
        ignition.reset();
      case ConnectionStatus.lost:
        // A reconnect is a quick re-light (DESIGN.md 7.12), not this sequence.
        break;
      case ConnectionStatus.connected:
        final reading = vehicle.rpm.value;
        if (!ignition.hasPlayed &&
            reading != null &&
            reading.value > ignitionRpm) {
          ignition.play();
        }
    }
  }

  final VehicleState vehicle;
  final Clock clock;

  /// The trip computer's signals (phase 4): ₹ this trip, ₹/km, km/L, the eco
  /// bar's value and the rest. Null where there is no trip computer (a Design
  /// Lab capture of a bare cluster); the clusters then leave those slots empty.
  /// Owned by whoever built it, not disposed here.
  final MoneySignals? money;

  /// Whether the data is Demo Mode's simulated car (CLAUDE.md 7.6): the DEMO
  /// badge is always visible while it is.
  final bool demoMode;

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

  /// The parked share (DESIGN.md 7.2), driven by [mode]: 1 parked, 0 in
  /// motion. The whole screen's Parked choreography reads this one value --
  /// the tach arc thinning and dimming, the hero shrinking to primary size,
  /// the status strip's captions -- so every piece moves on the same spring,
  /// staggered off it, and one built later never races one already on screen.
  late final ParkedShare parkedShare;

  /// The other way round: 1 in Motion, falling to 0 as the car parks. What
  /// gives way to the parked dock (the eco bar, the floor's trip readouts) fades
  /// on this, on the same spring.
  late final MappedShare motionShare = MappedShare(parkedShare, (p) => 1 - p);

  /// The parked-or-motion flag [parkedShare] follows, mapped off [_mode];
  /// not owned by the share, so [dispose] lets go of it separately.
  late final _MappedListenable<DrivingMode, bool> _parkedFlag;

  /// Motion or parked (DESIGN.md 7.2), straight from `VehicleState.mode`.
  ValueListenable<DrivingMode> get mode => _mode;

  /// The status strip's own small vocabulary (DESIGN.md 6.9), mapped from
  /// the session's real ConnectionStatus (DESIGN.md 7.12's full states are
  /// [linkPresentation]'s; this is only the adapter glyph).
  ValueListenable<AdapterLinkState> get adapter => _adapter;

  /// The raw connection status, for chrome that needs more than the
  /// adapter glyph's three states (DESIGN.md 7.12).
  ValueListenable<ConnectionStatus> get connection => _connection;

  /// Whether the phone has a usable GPS fix. Without a location source it is a
  /// plain "no fix", never an invented one.
  final ValueListenable<bool> gpsHasFix;

  /// Likewise: phone-temperature polling (CLAUDE.md 9) is cross-cutting app
  /// shell work, not yet wired to any page. A plain "not hot" rather than
  /// inventing one.
  /// Whether the phone is hot (DESIGN.md 6.9): a glyph in the status strip. It is
  /// the display controller's, when there is one.
  final ValueListenable<bool> phoneHot;

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
    vehicle.rpm.removeListener(_maybeIgnite);
    _connection.removeListener(_maybeIgnite);
    _connection.removeListener(_onConnection);
    linkPresentation.dispose();
    arcWave.dispose();
    horizonDraw.dispose();
    flankAway.dispose();
    flankDriver.dispose();
    ignition.dispose();
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
    motionShare.dispose();
    parkedShare.dispose();
    _parkedFlag.dispose();
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
