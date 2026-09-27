import '../../vehicle/sensor.dart';

/// A Mode 01 PID: what it is called, how many data bytes it carries, and how
/// they are decoded (CLAUDE.md 8.3, SAE J1979).
class Pid {
  const Pid({
    required this.id,
    required this.name,
    required this.sensor,
    required this.length,
    required this.formula,
  });

  final int id;
  final String name;

  /// The sensor it reads.
  final Sensor sensor;

  /// The number of data bytes after the PID in an answer.
  final int length;

  final double Function(List<int> data) formula;

  /// The value of [data], which must be [length] bytes, each 0 to 255.
  double decode(List<int> data) {
    if (data.length != length) {
      throw ArgumentError.value(
        data,
        'data',
        '$name has $length data byte${length == 1 ? '' : 's'}',
      );
    }
    for (final byte in data) {
      if (byte < 0 || byte > 255) {
        throw ArgumentError.value(data, 'data', 'not a byte: $byte');
      }
    }
    return formula(data);
  }

  @override
  String toString() =>
      'Pid(${id.toRadixString(16).toUpperCase().padLeft(2, '0')} $name)';
}

double _percent(List<int> d) => d[0] * 100 / 255;
double _minus40(List<int> d) => d[0] - 40.0;
double _byte(List<int> d) => d[0].toDouble();
double _quarter(List<int> d) => (256 * d[0] + d[1]) / 4;
double _hundredth(List<int> d) => (256 * d[0] + d[1]) / 100;
double _thousandth(List<int> d) => (256 * d[0] + d[1]) / 1000;
double _twentieth(List<int> d) => (256 * d[0] + d[1]) / 20;

/// The PIDs TapeDash reads.
abstract final class Pids {
  static const Pid load = Pid(
    id: 0x04,
    name: 'Engine load',
    sensor: Sensor.load,
    length: 1,
    formula: _percent,
  );
  static const Pid coolant = Pid(
    id: 0x05,
    name: 'Coolant temperature',
    sensor: Sensor.coolant,
    length: 1,
    formula: _minus40,
  );
  static const Pid manifoldPressure = Pid(
    id: 0x0B,
    name: 'Intake manifold pressure',
    sensor: Sensor.manifoldPressure,
    length: 1,
    formula: _byte,
  );
  static const Pid rpm = Pid(
    id: 0x0C,
    name: 'Engine speed',
    sensor: Sensor.rpm,
    length: 2,
    formula: _quarter,
  );
  static const Pid speed = Pid(
    id: 0x0D,
    name: 'Vehicle speed',
    sensor: Sensor.speed,
    length: 1,
    formula: _byte,
  );
  static const Pid intakeAir = Pid(
    id: 0x0F,
    name: 'Intake air temperature',
    sensor: Sensor.intakeAir,
    length: 1,
    formula: _minus40,
  );
  static const Pid airFlow = Pid(
    id: 0x10,
    name: 'Mass air flow',
    sensor: Sensor.airFlow,
    length: 2,
    formula: _hundredth,
  );
  static const Pid throttle = Pid(
    id: 0x11,
    name: 'Throttle position',
    sensor: Sensor.throttle,
    length: 1,
    formula: _percent,
  );
  static const Pid fuelLevel = Pid(
    id: 0x2F,
    name: 'Fuel level',
    sensor: Sensor.fuelLevel,
    length: 1,
    formula: _percent,
  );
  static const Pid voltage = Pid(
    id: 0x42,
    name: 'Module voltage',
    sensor: Sensor.voltage,
    length: 2,
    formula: _thousandth,
  );
  static const Pid fuelRate = Pid(
    id: 0x5E,
    name: 'Engine fuel rate',
    sensor: Sensor.fuelRate,
    length: 2,
    formula: _twentieth,
  );

  static const List<Pid> all = [
    load,
    coolant,
    manifoldPressure,
    rpm,
    speed,
    intakeAir,
    airFlow,
    throttle,
    fuelLevel,
    voltage,
    fuelRate,
  ];

  static final Map<int, Pid> _byId = {for (final p in all) p.id: p};

  /// The PID with this number, or null if TapeDash does not read it.
  static Pid? byId(int id) => _byId[id];

  /// The PID that reads [sensor].
  static Pid forSensor(Sensor sensor) =>
      all.firstWhere((p) => p.sensor == sensor);
}

/// One PID's data in an answer, and what it decodes to.
class PidValue {
  const PidValue(this.pid, this.data, this.value);

  final Pid pid;
  final List<int> data;
  final double value;
}

/// The values in an ECU's answer to a Mode 01 request: `41`, then each PID
/// followed by its data bytes.
class Mode01Answer {
  const Mode01Answer(this.values, {required this.complete});

  /// The values, in the order they appear.
  final List<PidValue> values;

  /// False if the answer has bytes that could not be read: a PID that is not
  /// one TapeDash knows (so its length is unknown), or data cut short.
  final bool complete;

  /// The value of [pid] in this answer, or null if it is not there.
  PidValue? valueOf(Pid pid) {
    for (final v in values) {
      if (identical(v.pid, pid)) return v;
    }
    return null;
  }

  /// Reads [message], or returns null if it is not a Mode 01 answer.
  static Mode01Answer? parse(List<int> message) {
    if (message.length < 2 || message.first != 0x41) return null;
    final values = <PidValue>[];
    var i = 1;
    var complete = true;
    while (i < message.length) {
      final pid = Pids.byId(message[i]);
      if (pid == null || i + 1 + pid.length > message.length) {
        complete = false;
        break;
      }
      final data = message.sublist(i + 1, i + 1 + pid.length);
      values.add(PidValue(pid, data, pid.decode(data)));
      i += 1 + pid.length;
    }
    return Mode01Answer(values, complete: complete);
  }
}

/// PID 01: the check-engine light, the number of stored codes, and the kind of
/// engine.
class MonitorStatus {
  const MonitorStatus({
    required this.milOn,
    required this.codeCount,
    required this.compressionIgnition,
  });

  /// The malfunction indicator lamp, the check-engine light.
  final bool milOn;

  /// How many fault codes are stored, 0 to 127.
  final int codeCount;

  /// True for a diesel: bit 3 of the second byte.
  final bool compressionIgnition;

  /// PID 01 has four data bytes.
  static MonitorStatus decode(List<int> data) {
    if (data.length != 4) {
      throw ArgumentError.value(data, 'data', 'PID 01 has 4 data bytes');
    }
    return MonitorStatus(
      milOn: data[0] & 0x80 != 0,
      codeCount: data[0] & 0x7F,
      compressionIgnition: data[1] & 0x08 != 0,
    );
  }

  @override
  String toString() =>
      'MonitorStatus(mil: $milOn, codes: $codeCount, diesel: $compressionIgnition)';
}
