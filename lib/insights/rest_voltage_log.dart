import 'dart:convert';

import '../core/clock.dart';
import '../core/key_value_store.dart';
import '../vehicle/vehicle_state.dart';

/// One reading of the battery at rest.
class RestReading {
  const RestReading(this.at, this.volts);
  final DateTime at;
  final double volts;
}

/// The battery's voltage with the ignition on and the engine off (Current): the
/// slow tell of an ageing battery. A trip starts when the engine does, so its
/// samples never hold one; this keeps one reading a day, from the settled voltage
/// before the engine starts.
class RestVoltageLog {
  RestVoltageLog({required this.store, required this.clock});

  static const _key = 'rest_voltage_log';

  /// Readings kept, oldest dropped first.
  static const int keep = 120;

  /// A reading is kept at most this often, so a day of short stops is one point.
  static const Duration spacing = Duration(hours: 6);

  /// A battery at rest reads between these; outside it the reading is the
  /// alternator, a charger or a fault, and says nothing about the battery.
  static const double minVolts = 11.0;
  static const double maxVolts = 13.0;

  /// The voltage must hold within [settle] volts for [settleFor] to count as
  /// settled.
  static const double settle = 0.06;
  static const Duration settleFor = Duration(seconds: 8);

  final KeyValueStore store;
  final Clock clock;

  List<RestReading> _readings = const [];

  /// Oldest first.
  List<RestReading> get readings => _readings;

  Future<void> load() async {
    final text = await store.getString(_key);
    if (text == null) return;
    try {
      final list = jsonDecode(text) as List<dynamic>;
      _readings = [
        for (final e in list)
          RestReading(
            DateTime.fromMillisecondsSinceEpoch((e as List<dynamic>)[0] as int),
            (e[1] as num).toDouble(),
          ),
      ];
    } on Object {
      _readings = const [];
    }
  }

  /// Keeps [volts] if it is a battery at rest and it has been long enough since
  /// the last. Returns whether it was kept.
  Future<bool> note(double volts) async {
    if (volts < minVolts || volts > maxVolts) return false;
    final now = clock.now();
    if (_readings.isNotEmpty && now.difference(_readings.last.at) < spacing) {
      return false;
    }
    _readings = [..._readings, RestReading(now, volts)];
    if (_readings.length > keep) {
      _readings = _readings.sublist(_readings.length - keep);
    }
    await store.setString(
      _key,
      jsonEncode([
        for (final r in _readings) [r.at.millisecondsSinceEpoch, r.volts],
      ]),
    );
    return true;
  }

  Future<void> clear() async {
    _readings = const [];
    await store.remove(_key);
  }
}

/// Watches a car's voltage and gives the log one settled reading each time the
/// ignition is on and the engine is not.
class RestVoltageWatcher {
  RestVoltageWatcher({required this.vehicle, required this.log}) {
    vehicle.voltage.addListener(_onVoltage);
    vehicle.engineRunning.addListener(_onEngine);
  }

  final VehicleState vehicle;
  final RestVoltageLog log;

  double? _anchor;
  Duration? _since;
  bool _done = false;

  void _onEngine() {
    _anchor = null;
    _since = null;
    // Each time the engine stops is a new chance for a reading.
    _done = vehicle.engineRunning.value;
  }

  void _onVoltage() {
    final r = vehicle.voltage.value;
    if (r == null || _done) return;
    if (vehicle.engineRunning.value ||
        vehicle.ignition.value != IgnitionState.on) {
      return;
    }
    final now = log.clock.monotonic();
    final anchor = _anchor;
    if (anchor == null || (r.value - anchor).abs() > RestVoltageLog.settle) {
      _anchor = r.value;
      _since = now;
      return;
    }
    if (now - _since! >= RestVoltageLog.settleFor) {
      _done = true;
      log.note(r.value);
    }
  }

  void dispose() {
    vehicle.voltage.removeListener(_onVoltage);
    vehicle.engineRunning.removeListener(_onEngine);
  }
}
