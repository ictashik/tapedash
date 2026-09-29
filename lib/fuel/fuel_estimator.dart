import 'dart:math' as math;

import '../core/observable.dart';
import '../vehicle/reading.dart';
import '../vehicle/sensor.dart';
import '../vehicle/vehicle_state.dart';
import 'fuel_constants.dart';
import 'fuel_math.dart';

/// Where the fuel flow comes from (CLAUDE.md 8.4), best first.
enum FuelSource {
  /// PID 5E, the engine's own fuel rate: used as it is.
  fuelRate('5E'),

  /// PID 10, the air mass flow, over the air-fuel ratio.
  airFlow('MAF'),

  /// The manifold pressure, the intake temperature and the revs, with the
  /// engine's displacement.
  speedDensity('MAP'),

  /// Nothing the car reports says how much fuel it burns.
  none('NONE');

  const FuelSource(this.label);

  /// Shown on the Diagnostics page.
  final String label;
}

/// One estimate of how fast fuel is burning, before calibration.
class FuelFlow {
  const FuelFlow({
    required this.litresPerHour,
    required this.source,
    required this.at,
    required this.receivedAt,
    this.lowConfidence = false,
    this.cutOff = false,
  });

  final double litresPerHour;
  final FuelSource source;

  /// When the sensor it comes from was measured, on the monotonic clock.
  final Duration at;
  final Duration receivedAt;

  /// The method is not sound for this engine (a diesel's air flow): the figure
  /// is a rough one until a fill-up has calibrated it.
  final bool lowConfidence;

  /// The car looked to be coasting with the fuel cut, so an air-based estimate
  /// was taken as no fuel.
  final bool cutOff;
}

/// Picks the best fuel-flow source the car offers and turns its readings into
/// litres an hour (CLAUDE.md 8.4).
///
/// It follows the [VehicleState]: an estimate is made each time the chosen
/// source's sensor is read. A source that has gone stale hands over to the next
/// best, and with none, [source] is [FuelSource.none] and there are no
/// estimates, which is how the UI knows to say money is unavailable.
class FuelEstimator {
  FuelEstimator({required this.vehicle, required this.setup}) {
    for (final sensor in _watched) {
      void listener() => _onReading(sensor);
      _listeners[sensor] = listener;
      vehicle.reading(sensor).addListener(listener);
    }
    vehicle.throttle.addListener(_onThrottle);
  }

  /// The lowest throttle reading seen while idling: where this car's closed
  /// throttle reads. PID 11 is the absolute position, which reads 10 to 20% with
  /// the throttle shut, so "throttle at 0" (CLAUDE.md 8.4) is judged from here,
  /// not from 0. Null until the car has idled.
  double? _closedThrottle;

  /// How far above the closed reading still counts as closed.
  static const double closedMarginPercent = 1.5;

  void _onThrottle() {
    final t = vehicle.throttle.value;
    final speed = vehicle.speed.value;
    final rpm = vehicle.rpm.value;
    if (t == null || speed == null || rpm == null) return;
    if (speed.value < 2 && rpm.value < 1500 && rpm.value > 400) {
      final v = t.value;
      if (_closedThrottle == null || v < _closedThrottle!) _closedThrottle = v;
    }
  }

  /// Where the throttle reads when it is closed, if it has been seen.
  double? get closedThrottle => _closedThrottle;

  static const _watched = [
    Sensor.fuelRate,
    Sensor.airFlow,
    Sensor.manifoldPressure,
  ];

  final VehicleState vehicle;
  VehicleSetup setup;

  final ObservableValue<FuelFlow?> _flow = ObservableValue(null);
  final ObservableValue<FuelSource> _source = ObservableValue(FuelSource.none);
  final Map<Sensor, void Function()> _listeners = {};

  /// The latest estimate, in litres an hour. Null before the first.
  Observable<FuelFlow?> get flow => _flow;

  /// The source in use now.
  Observable<FuelSource> get source => _source;

  /// The sensor a source reads its main value from.
  static Sensor sensorOf(FuelSource source) => switch (source) {
    FuelSource.fuelRate => Sensor.fuelRate,
    FuelSource.airFlow => Sensor.airFlow,
    FuelSource.speedDensity => Sensor.manifoldPressure,
    FuelSource.none => throw ArgumentError('none has no sensor'),
  };

  /// The best source that has fresh readings, without changing anything.
  FuelSource pick() {
    if (!vehicle.isStale(Sensor.fuelRate)) return FuelSource.fuelRate;
    if (!vehicle.isStale(Sensor.airFlow)) return FuelSource.airFlow;
    if (!setup.isDiesel &&
        !vehicle.isStale(Sensor.manifoldPressure) &&
        !vehicle.isStale(Sensor.intakeAir) &&
        !vehicle.isStale(Sensor.rpm)) {
      return FuelSource.speedDensity;
    }
    return FuelSource.none;
  }

  void _onReading(Sensor sensor) {
    final chosen = pick();
    _source.value = chosen;
    if (chosen == FuelSource.none || sensorOf(chosen) != sensor) return;
    final reading = vehicle.reading(sensor).value;
    if (reading == null) return;
    final flow = estimate(chosen, reading);
    if (flow != null) _flow.value = flow;
  }

  /// The estimate from [source], given its own [reading], with the other
  /// sensors as they are now.
  FuelFlow? estimate(FuelSource source, Reading reading) {
    final c = setup.constants;
    switch (source) {
      case FuelSource.none:
        return null;
      case FuelSource.fuelRate:
        return FuelFlow(
          litresPerHour: reading.value,
          source: source,
          at: reading.at,
          receivedAt: reading.receivedAt,
        );
      case FuelSource.airFlow:
        return _airBased(
          source,
          reading,
          FuelMath.litresPerHourFromAirFlow(
            gramsPerSecond: reading.value,
            airFuelRatio: c.airFuelRatio,
            densityGramsPerLitre: c.densityGramsPerLitre,
          ),
        );
      case FuelSource.speedDensity:
        final rpm = vehicle.rpm.value;
        final iat = vehicle.intakeAir.value;
        if (rpm == null || iat == null) return null;
        final air = FuelMath.airFlowFromManifold(
          manifoldKpa: reading.value,
          intakeCelsius: iat.value,
          rpm: rpm.value,
          displacementLitres: setup.displacementLitres,
          volumetricEfficiency: c.volumetricEfficiencyAt(rpm.value),
          specificGasConstant: c.specificGasConstant,
        );
        return _airBased(
          source,
          reading,
          FuelMath.litresPerHourFromAirFlow(
            gramsPerSecond: air,
            airFuelRatio: c.airFuelRatio,
            densityGramsPerLitre: c.densityGramsPerLitre,
          ),
        );
    }
  }

  FuelFlow _airBased(FuelSource source, Reading reading, double litresPerHour) {
    final cut = _fuelCutSuspected();
    return FuelFlow(
      litresPerHour: cut ? 0 : litresPerHour,
      source: source,
      at: reading.at,
      receivedAt: reading.receivedAt,
      lowConfidence: setup.isDiesel,
      cutOff: cut,
    );
  }

  /// A petrol car with the throttle closed, above [FuelConstants.cutOffMinSpeedKmh]
  /// and [FuelConstants.cutOffMinRpm], is being driven by its wheels and its
  /// injectors are shut (CLAUDE.md 8.4). A diesel's air flow is not used as fuel
  /// at all when it does this, and a car whose throttle is not read is never
  /// judged to be cutting.
  bool _fuelCutSuspected() {
    final c = setup.constants;
    final throttle = vehicle.throttle.value;
    final rpm = vehicle.rpm.value;
    final speed = vehicle.speed.value;
    if (throttle == null || rpm == null || speed == null) return false;
    if (vehicle.isStale(Sensor.throttle) ||
        vehicle.isStale(Sensor.rpm) ||
        vehicle.isStale(Sensor.speed)) {
      return false;
    }
    final closed = math.max(
      c.cutOffMaxThrottlePercent,
      _closedThrottle == null ? 0 : _closedThrottle! + closedMarginPercent,
    );
    return throttle.value <= closed &&
        rpm.value > c.cutOffMinRpm &&
        speed.value > c.cutOffMinSpeedKmh;
  }

  void dispose() {
    _listeners.forEach(
      (sensor, l) => vehicle.reading(sensor).removeListener(l),
    );
    _listeners.clear();
  }
}
