import 'dart:async';

import '../coach/coach_monitor.dart';
import '../coach/hard_event_detector.dart';
import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../fuel/fuel_estimator.dart';
import '../location/location_source.dart';
import '../money/fuel_ledger.dart';
import '../money/trip_computer.dart';
import '../obd/obd_session.dart' show ConnectionStatus;
import '../vehicle/sensor.dart';
import '../vehicle/vehicle_state.dart';
import 'trip.dart';

/// Where the recorder is (CLAUDE.md 8.6).
enum TripPhase {
  /// No trip.
  none,

  /// A trip is going on.
  running,

  /// The engine looks to be off, and has been for less than the ten seconds
  /// that make it so.
  ending,

  /// The trip has ended and can still be resumed, for five minutes.
  ended,
}

/// The rules of a trip's start and end (CLAUDE.md 8.6), as numbers.
class TripRules {
  const TripRules({
    this.engineOffAfter = const Duration(seconds: 10),
    this.resumeWithin = const Duration(minutes: 5),
    this.lostEndsAfter = const Duration(minutes: 5),
    this.sampleEvery = const Duration(seconds: 1),
    this.saveEvery = const Duration(seconds: 10),
    this.engineOffBelowVolts = 13,
  });

  /// The engine has to look off this long for the trip to end.
  final Duration engineOffAfter;

  /// An engine that starts again within this long takes the same trip up.
  final Duration resumeWithin;

  /// A link that has been down this long, with the engine last seen running,
  /// ends the trip: nothing is being recorded, and nothing says it is going on.
  final Duration lostEndsAfter;

  final Duration sampleEvery;
  final Duration saveEvery;

  final double engineOffBelowVolts;
}

/// Starts, keeps and ends trips (CLAUDE.md 8.6).
///
/// **A trip starts** when the engine starts (rpm above 400). **It ends** when
/// the engine has been off for ten seconds: the rpm is 0 and the module voltage
/// is below about 13 V, or the ECU has stopped answering. Standing still with
/// the engine running (traffic, signals, a jam) never ends a trip, and neither
/// does a lost adapter link, since that says nothing about the engine. **If the
/// engine starts again within five minutes,** the same trip carries on.
///
/// Every second while the engine runs, a sample is taken for the route and the
/// telemetry; samples and totals are saved to [repository] in batches. The
/// database is asynchronous and the recorder is not, so writes are queued in
/// order and [idle] completes when they have all been made.
class TripRecorder {
  TripRecorder({
    required this.vehicle,
    required this.connection,
    required this.computer,
    required this.hardEvents,
    required this.estimator,
    required this.repository,
    required this.clock,
    required this.scheduler,
    required this.calibrationFactor,
    required this.price,
    this.ledger,
    this.coach,
    this.location,
    this.isDemo = false,
    this.rules = const TripRules(),
  }) {
    vehicle.engineRunning.addListener(_evaluate);
    vehicle.reading(Sensor.voltage).addListener(_evaluate);
    connection.addListener(_evaluate);
    hardEvents.onEvent(_onHardEvent);
    _fixes = location?.fixes.listen((f) => _lastFix = f);
    _evaluate();
  }

  final VehicleState vehicle;
  final Observable<ConnectionStatus> connection;
  final TripComputer computer;
  final HardEventDetector hardEvents;
  final FuelEstimator estimator;
  final TripRepository repository;
  final Clock clock;
  final Scheduler scheduler;
  final double Function() calibrationFactor;
  final Observable<double?> price;
  final FuelLedger? ledger;

  /// Counts the long idles, high revs and speeding of the trip, if given.
  final CoachMonitor? coach;
  final LocationSource? location;
  final bool isDemo;
  final TripRules rules;

  final ObservableValue<TripPhase> _phase = ObservableValue(TripPhase.none);
  final ObservableValue<Trip?> _current = ObservableValue(null);
  final List<void Function(Trip)> _startedListeners = [];
  final List<void Function(Trip)> _endedListeners = [];
  final List<void Function(Trip)> _resumedListeners = [];

  StreamSubscription<LocationFix>? _fixes;
  LocationFix? _lastFix;

  Trip? _trip;
  int? _id;
  Future<void> _chain = Future.value();
  final List<TripSample> _buffer = [];
  Duration? _startedMono;
  double _engineSeconds = 0;
  int _hardAccelerations = 0;
  int _hardBrakings = 0;

  ScheduledTask? _sampleTask;
  ScheduledTask? _offTask;
  ScheduledTask? _resumeTask;
  ScheduledTask? _lostTask;
  Duration? _offSince;
  DateTime? _endedAt;

  /// Where the recorder is.
  Observable<TripPhase> get phase => _phase;

  /// The trip going on, or the one that has just ended, as a snapshot kept
  /// current once a second. Null before the first trip.
  Observable<Trip?> get current => _current;

  /// Whether a trip is being recorded: the poller moves the fuel PID to the fast
  /// tier while it is (CLAUDE.md 8.2).
  bool get recording =>
      _phase.value == TripPhase.running || _phase.value == TripPhase.ending;

  /// Completes when every write queued so far has been made.
  Future<void> get idle => _chain;

  void onTripStarted(void Function(Trip) l) => _startedListeners.add(l);

  /// Called when a trip ends: the Debrief begins (DESIGN.md 7.5).
  void onTripEnded(void Function(Trip) l) => _endedListeners.add(l);

  /// Called when an ended trip is taken up again.
  void onTripResumed(void Function(Trip) l) => _resumedListeners.add(l);

  // ------------------------------------------------------------ the rules

  bool get _engineOn => vehicle.engineRunning.value;

  /// Whether the engine is known to be off: the car has stopped answering, or it
  /// answers with the revs at 0 and the battery not being charged.
  bool get _engineOff {
    final status = connection.value;
    if (status == ConnectionStatus.waitingForIgnition) return true;
    if (status != ConnectionStatus.connected) return false;
    if (_engineOn) return false;
    if (vehicle.rpm.value == null) return false;
    final volts = vehicle.voltage.value?.value;
    return volts == null || volts < rules.engineOffBelowVolts;
  }

  void _evaluate() {
    final status = connection.value;
    switch (_phase.value) {
      case TripPhase.none:
        if (_engineOn && status == ConnectionStatus.connected) _startNew();
      case TripPhase.ended:
        if (_engineOn && status == ConnectionStatus.connected) _resume();
      case TripPhase.running:
        if (_engineOff) {
          _beginEnding();
        } else if (status == ConnectionStatus.lost ||
            status == ConnectionStatus.searching) {
          _lostTask ??= scheduler.runAfter(rules.lostEndsAfter, () {
            _lostTask = null;
            if (_phase.value == TripPhase.running) _finalize(clock.monotonic());
          });
        } else {
          _lostTask?.cancel();
          _lostTask = null;
        }
      case TripPhase.ending:
        if (!_engineOff) {
          _offTask?.cancel();
          _offTask = null;
          _offSince = null;
          _phase.value = TripPhase.running;
        }
    }
  }

  /// Ends the trip now, for good: the next engine start is a new trip, not a
  /// resumed one. The demo drive starting over is one such moment, and Garage's
  /// END TRIP another. Nothing if no trip is going.
  void endNow() {
    if (_phase.value != TripPhase.running && _phase.value != TripPhase.ending) {
      return;
    }
    _offTask?.cancel();
    _offTask = null;
    computer.engineOff();
    _finalize(clock.monotonic());
    // The resume window is for an engine that was switched off; this was ended.
    _resumeTask?.cancel();
    _resumeTask = null;
    _phase.value = TripPhase.none;
  }

  // ------------------------------------------------------------ lifecycle

  void _startNew() {
    computer.reset();
    coach?.reset();
    _engineSeconds = 0;
    _hardAccelerations = 0;
    _hardBrakings = 0;
    _buffer.clear();
    _startedMono = clock.monotonic();
    final trip = Trip(startedAt: clock.now(), isDemo: isDemo);
    _trip = trip;
    _id = null;
    _endedAt = null;
    _phase.value = TripPhase.running;
    _queue(() async {
      final saved = await repository.create(trip);
      _id = saved.id;
      _trip = _trip!.copyWith(id: saved.id);
    });
    _startSampling();
    _publish();
    for (final l in List.of(_startedListeners)) {
      l(trip);
    }
  }

  void _resume() {
    _resumeTask?.cancel();
    _resumeTask = null;
    _endedAt = null;
    _phase.value = TripPhase.running;
    _trip = _trip!.copyWith(endedAt: null);
    _queue(() async => repository.update(_snapshot()));
    _startSampling();
    _publish();
    for (final l in List.of(_resumedListeners)) {
      l(_trip!);
    }
  }

  void _beginEnding() {
    _phase.value = TripPhase.ending;
    _offSince = clock.monotonic();
    computer.engineOff();
    _offTask = scheduler.runAfter(rules.engineOffAfter, () {
      _offTask = null;
      if (_phase.value == TripPhase.ending) _finalize(_offSince!);
    });
  }

  void _finalize(Duration offAt) {
    _sampleTask?.cancel();
    _sampleTask = null;
    _lostTask?.cancel();
    _lostTask = null;
    computer.finish();
    // The trip ended when the engine went off, not when that was certain.
    final ago = clock.monotonic() - offAt;
    _endedAt = clock.now().subtract(ago);
    _trip = _snapshot().copyWith(endedAt: _endedAt);
    _phase.value = TripPhase.ended;
    _flushSamples();
    _queue(() async {
      await repository.update(_trip!);
      await ledger?.flush();
    });
    _publish();
    _resumeTask = scheduler.runAfter(rules.resumeWithin - ago, () {
      _resumeTask = null;
      if (_phase.value == TripPhase.ended) _phase.value = TripPhase.none;
    });
    for (final l in List.of(_endedListeners)) {
      l(_trip!);
    }
  }

  // ------------------------------------------------------------- sampling

  void _startSampling() {
    _sampleTask?.cancel();
    var sinceSave = Duration.zero;
    _sampleTask = scheduler.runEvery(rules.sampleEvery, () {
      if (_engineOn) {
        _engineSeconds += rules.sampleEvery.inMicroseconds / 1e6;
        _takeSample();
      }
      _publish();
      sinceSave += rules.sampleEvery;
      if (sinceSave >= rules.saveEvery) {
        sinceSave = Duration.zero;
        _flushSamples();
        _queue(() async => repository.update(_snapshot()));
        ledger?.flush();
      }
    });
  }

  void _takeSample() {
    final speed = vehicle.speed.value;
    if (speed == null) return;
    final flow = estimator.flow.value;
    final fix = _lastFix;
    _buffer.add(
      TripSample(
        seconds: (clock.monotonic() - _startedMono!).inMicroseconds / 1e6,
        speedKmh: speed.value,
        rpm: vehicle.rpm.value?.value ?? 0,
        throttle: vehicle.throttle.value?.value ?? 0,
        litresPerHour: (flow?.litresPerHour ?? 0) * calibrationFactor(),
        latitude: fix?.latitude,
        longitude: fix?.longitude,
      ),
    );
  }

  void _flushSamples() {
    if (_buffer.isEmpty) return;
    final batch = List.of(_buffer);
    _buffer.clear();
    _queue(() async {
      if (_id != null) await repository.addSamples(_id!, batch);
    });
  }

  void _onHardEvent(HardEvent e) {
    if (_phase.value == TripPhase.none) return;
    if (e.type == HardEventType.hardAcceleration) {
      _hardAccelerations++;
    } else {
      _hardBrakings++;
    }
  }

  // ---------------------------------------------------------------- state

  Trip _snapshot() {
    final pr = price.value;
    final litres = computer.litres.value;
    return (_trip ?? Trip(startedAt: clock.now(), isDemo: isDemo)).copyWith(
      id: _id,
      distanceKm: computer.distanceKm.value,
      litres: litres,
      uncalibratedLitres: computer.uncalibratedLitres,
      cost: pr == null ? null : litres * pr,
      pricePerLitre: pr,
      idleSeconds: computer.idleSeconds.value,
      engineSeconds: _engineSeconds,
      bucketLitres: computer.bucketLitres,
      blockBuckets: [for (final b in computer.blocks) b.bucket],
      fuelSource: estimator.source.value,
      lowConfidence: computer.lowConfidence,
      calibrationFactor: calibrationFactor(),
      hardAccelerations: _hardAccelerations,
      hardBrakings: _hardBrakings,
      longIdles: coach?.stats.value.longIdles ?? 0,
      longestIdleSeconds: coach?.stats.value.longestIdleSeconds ?? 0,
      highRpmSeconds: coach?.stats.value.highRpmSeconds ?? 0,
      speedingSeconds: coach?.stats.value.speedingSeconds ?? 0,
    );
  }

  void _publish() {
    if (_trip == null) return;
    _trip = _snapshot().copyWith(endedAt: _endedAt);
    _current.value = _trip;
  }

  void _queue(Future<void> Function() op) {
    _chain = _chain.then((_) => op()).catchError((Object _) {});
  }

  /// Saves what there is, and stops. A trip still going is left open, to be
  /// picked up (its record is the last saved).
  Future<void> close() async {
    _sampleTask?.cancel();
    _offTask?.cancel();
    _resumeTask?.cancel();
    _lostTask?.cancel();
    vehicle.engineRunning.removeListener(_evaluate);
    vehicle.reading(Sensor.voltage).removeListener(_evaluate);
    connection.removeListener(_evaluate);
    await _fixes?.cancel();
    if (_trip != null && _phase.value != TripPhase.none) {
      _flushSamples();
      _queue(() async => repository.update(_snapshot()));
    }
    await _chain;
  }
}
