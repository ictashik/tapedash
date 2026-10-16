import 'dart:math' as math;

import 'profiles.dart';
import 'sim_random.dart';
import 'simulated_car.dart';
import 'vehicle_model.dart' show VehicleSnapshot;
import 'vehicle_profile.dart';

/// A fault code as the bytes an ECU sends, and back. The first two bits of the
/// first byte are the letter (P, C, B or U), the next two the first digit, and
/// the rest three hex digits (ELM327 datasheet, "Interpreting Trouble Codes").
abstract final class DtcCodec {
  static const String _letters = 'PCBU';

  /// The two bytes for a code such as `P0420`, or null if it is not one.
  static List<int>? encode(String code) {
    final match = RegExp(
      r'^([PCBU])([0-3])([0-9A-F]{3})$',
    ).firstMatch(code.toUpperCase());
    if (match == null) return null;
    final letter = _letters.indexOf(match.group(1)!);
    final first = int.parse(match.group(2)!);
    final rest = int.parse(match.group(3)!, radix: 16);
    final value = (letter << 14) | (first << 12) | rest;
    return [value >> 8, value & 0xFF];
  }

  /// The code for two bytes.
  static String decode(int high, int low) {
    final value = (high << 8) | low;
    final letter = _letters[(value >> 14) & 3];
    final first = (value >> 12) & 3;
    final rest = (value & 0xFFF)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(3, '0');
    return '$letter$first$rest';
  }
}

/// The supported-PID bitmask of Mode 01 (SAE J1979): four bytes for the 32 PIDs
/// after [base], with the top bit for the first of them and the last bit for
/// the next range's own support PID.
abstract final class SupportMask {
  static List<int> encode(Iterable<int> pids, int base) {
    final set = pids.toSet();
    var mask = 0;
    for (var pid = base + 1; pid <= base + 0x20; pid++) {
      if (set.contains(pid)) mask |= 1 << (32 - (pid - base));
    }
    // The last bit says whether the next range has any PIDs at all.
    if (set.any((p) => p > base + 0x20)) mask |= 1;
    return [
      (mask >> 24) & 0xFF,
      (mask >> 16) & 0xFF,
      (mask >> 8) & 0xFF,
      mask & 0xFF,
    ];
  }
}

/// What the adapter simulator needs from the car: whether the bus is alive, the
/// battery voltage at the OBD socket, and an ECU that answers requests.
abstract interface class ObdEcu {
  /// Whether the ECU is powered and answering: the ignition is on.
  bool get isAwake;

  /// The battery voltage at the OBD socket. It is there with the ignition off
  /// too, so the adapter can read it whether or not the ECU answers.
  double get batteryVolts;

  /// The payload of the ECU's reply to a request, or null if it does not
  /// answer at all (which the adapter reports as `NO DATA`). A request is the
  /// mode byte followed by its PIDs, without any CAN framing.
  List<int>? respond(List<int> request);
}

/// The car's engine control unit: it answers OBD-II requests with the bytes a
/// real ECU would send, from the simulated car's state (CLAUDE.md 7.4).
///
/// It knows nothing of the adapter. Its answers are the payload of a CAN
/// message, without the CAN framing, which the adapter simulator adds.
class SimulatedEcu implements ObdEcu {
  SimulatedEcu({
    required this.car,
    this.vin = 'TAPEDASHSIM000001',
    int? noiseSeed,
    this.pids,
    this.surveyData = false,
    this.calibrationId = 'TAPEDASH-SIM-CAL-1',
  }) : _noise = SimRandom(noiseSeed ?? car.seed).fork(2);

  /// The ECUs a car's profile gives it, the first to answer first. A one-ECU
  /// profile gives the plain ECU; a profile with a second set of PIDs gives two,
  /// which also answer the modes a survey asks about.
  static List<SimulatedEcu> forCar(SimulatedCar car) {
    final second = car.profile.secondEcuPids;
    if (second.isEmpty) return [SimulatedEcu(car: car)];
    return [
      SimulatedEcu(
        car: car,
        surveyData: true,
        calibrationId: 'TAPEDASH-SIM-ECM',
      ),
      SimulatedEcu(
        car: car,
        pids: second,
        surveyData: true,
        calibrationId: 'TAPEDASH-SIM-PCM',
        noiseSeed: car.seed + 1,
      ),
    ];
  }

  final SimulatedCar car;

  /// The 17-character vehicle identification number.
  final String vin;

  /// The PIDs this ECU answers, when it is not the profile's own: a second ECU
  /// on the bus has its own set.
  final Set<int>? pids;

  /// Whether the ECU also answers the modes only a survey asks about: Mode 06
  /// (test results), Mode 0A (permanent codes) and Mode 09's calibration IDs.
  /// Left off, it is the plain ECU the rest of the app is tested against.
  final bool surveyData;

  /// What Mode 09 PID 04 returns, when [surveyData] is on.
  final String calibrationId;

  // Sensor noise comes from its own stream, so polling more or less often
  // never changes what the car does.
  final SimRandom _noise;

  VehicleProfile get profile => car.profile;

  @override
  bool get isAwake => car.state.ignitionOn;

  @override
  double get batteryVolts => car.state.voltage;

  /// The PIDs this ECU answers: the profile's, and PID 01, which every OBD-II
  /// ECU has.
  Set<int> get supportedPids => {0x01, ...(pids ?? profile.supportedPids)};

  @override
  List<int>? respond(List<int> request) {
    if (request.isEmpty || !isAwake) return null;
    return switch (request.first) {
      0x01 => _mode01(request.skip(1).toList()),
      0x03 => _dtcReply(0x43, car.storedDtcs),
      0x07 => _dtcReply(0x47, car.pendingDtcs),
      0x04 => _clearCodes(),
      0x09 => _mode09(request.skip(1).toList()),
      0x06 when surveyData => _mode06(request.skip(1).toList()),
      0x0A when surveyData => _dtcReply(0x4A, const []),
      _ => null,
    };
  }

  // ------------------------------------------------------------------ mode 01

  /// A request can ask for at most six PIDs (SAE J1979); an ECU ignores one
  /// that asks for more.
  static const int maxPidsPerRequest = 6;

  List<int>? _mode01(List<int> pids) {
    if (pids.isEmpty || pids.length > maxPidsPerRequest) return null;
    final reply = <int>[0x41];
    for (final pid in pids) {
      final data = mode01(pid);
      if (data != null) {
        reply
          ..add(pid)
          ..addAll(data);
      }
    }
    return reply.length > 1 ? reply : null;
  }

  /// The data bytes for one Mode 01 PID, or null if it is not supported.
  List<int>? mode01(int pid) {
    if (pid == 0x00 || pid == 0x20 || pid == 0x40 || pid == 0x60) {
      final mask = SupportMask.encode(supportedPids, pid);
      // A range's own PID is only there if the range has something in it.
      if (pid != 0 && mask.every((b) => b == 0)) return null;
      return mask;
    }
    if (!supportedPids.contains(pid)) return null;
    final s = car.state;
    switch (pid) {
      case 0x01:
        // A: the check-engine light and how many codes are stored. B: the
        // three continuous monitors are supported and complete, and bit 3 says
        // compression ignition. C and D: the other monitors, all complete.
        final count = math.min(car.storedDtcs.length, 127);
        return [
          (car.milOn ? 0x80 : 0) | count,
          profile.isDiesel ? 0x0F : 0x07,
          0x65,
          0x00,
        ];
      case pidLoad:
        return [
          _percent(
            s.loadFraction + _noise.nextGaussian(standardDeviation: 0.004),
          ),
        ];
      case pidCoolant:
        return [_clampByte(s.coolantC.round() + 40)];
      case pidMap:
        return [
          _clampByte(
            (s.manifoldKpa + _noise.nextGaussian(standardDeviation: 0.25))
                .round(),
          ),
        ];
      case pidRpm:
        // The engine turns over at a few hundred rpm while it cranks, and the
        // ECU reports that; only a stopped engine reads exactly zero.
        final rpm = s.rpm > 0
            ? s.rpm + _noise.nextGaussian(standardDeviation: 3)
            : 0.0;
        return _word((math.max(0.0, rpm) * 4).round());
      case pidSpeed:
        return [_clampByte(s.speedKmh.round())];
      case pidIntakeAir:
        return [_clampByte(s.intakeAirC.round() + 40)];
      case pidMaf:
        final maf =
            s.airGramsPerSecond *
            (1 + _noise.nextGaussian(standardDeviation: 0.004));
        return _word((maf * 100).round());
      case pidThrottle:
        return [
          _percent(
            s.throttleFraction + _noise.nextGaussian(standardDeviation: 0.002),
          ),
        ];
      case pidFuelLevel:
        return [_percent(s.fuelLevelFraction)];
      case pidVoltage:
        return _word(
          ((s.voltage + _noise.nextGaussian(standardDeviation: 0.02)) * 1000)
              .round(),
        );
      case pidFuelRate:
        final rate =
            s.fuelRateLitresPerHour *
            (1 + _noise.nextGaussian(standardDeviation: 0.004));
        return _word((rate * 20).round());
    }
    return _extendedPid(pid, s);
  }

  // The PIDs beyond the ones TapeDash reads, which a survey asks for. Their
  // values are invented from the car's state, to be shaped right and to move
  // plausibly, not to be accurate: no real car's data went into them.

  /// The throttle plate with the pedal up, as a fraction (PID 11 does not read
  /// zero; see DECISIONS.md).
  static const double _plateClosed = 0.12;

  List<int>? _extendedPid(int pid, VehicleSnapshot s) {
    final plate = s.throttleFraction;
    final pedal = ((plate - _plateClosed) / (1 - _plateClosed)).clamp(0.0, 1.0);
    final heavy = s.loadFraction > 0.9;
    switch (pid) {
      case 0x03:
        // Closed loop, or open loop because of the load or a fuel cut.
        return [heavy || s.fuelCut ? 0x04 : 0x02, 0x00];
      case 0x06:
        return [
          _clampByte(128 + _noise.nextGaussian(standardDeviation: 1.5).round()),
        ];
      case 0x0E:
        final advance = 12 + 18 * (1 - s.loadFraction) + 4 * s.rpm / 6000;
        return [_clampByte(((advance + 64) * 2).round())];
      case 0x13:
        return [0x03];
      case 0x15:
        // The second oxygen sensor: its voltage, and no trim (FF).
        return [s.fuelCut ? 20 : 130, 0xFF];
      case 0x1F:
        return _word(s.engineRunning ? s.timeSeconds.round() : 0);
      case 0x21:
        return _word(0);
      case 0x2E:
        return [_percent(0.15 * (1 - pedal))];
      case 0x30:
        return [40];
      case 0x31:
        return _word(1234 + (s.distanceM / 1000).round());
      case 0x33:
        return [91];
      case 0x34:
        final phi = heavy ? 1.12 : 1.0;
        return [..._word((phi * 32768).round()), 0x80, 0x00];
      case 0x41:
        return [0x00, 0x07, 0xE5, 0x00];
      case 0x43:
        return _word((s.loadFraction * 255 * 1.05).round());
      case 0x44:
        return _word(((heavy ? 1.12 : 1.0) * 32768).round());
      case 0x45:
        return [_percent(pedal)];
      case 0x47:
      case 0x4C:
        return [_percent(plate)];
      case 0x49:
        return [_percent(pedal)];
      case 0x4A:
        return [_percent(pedal / 2)];
    }
    return null;
  }

  /// A fraction, 0 to 1, as a byte of 0 to 255.
  static int _percent(double fraction) => _clampByte((fraction * 255).round());

  static int _clampByte(int value) => value.clamp(0, 255);

  static List<int> _word(int value) {
    final v = value.clamp(0, 0xFFFF);
    return [v >> 8, v & 0xFF];
  }

  // -------------------------------------------------------------- fault codes

  /// A reply to Mode 03 or 07: the mode's reply byte, how many codes follow (a
  /// CAN ECU adds this byte), and two bytes for each.
  List<int> _dtcReply(int replyMode, List<String> codes) {
    final reply = <int>[replyMode, codes.length];
    for (final code in codes) {
      final bytes = DtcCodec.encode(code);
      if (bytes != null) reply.addAll(bytes);
    }
    return reply;
  }

  /// Mode 04. An ECU will not erase its codes while the car is moving, and says
  /// so with a negative response: 7F, the mode, and 22 for "conditions not
  /// correct".
  List<int> _clearCodes() {
    if (car.state.speedMs > 0.3) return [0x7F, 0x04, 0x22];
    car.clearDtcs();
    return [0x44];
  }

  // ------------------------------------------------------------------ mode 09

  List<int>? _mode09(List<int> pids) {
    if (pids.isEmpty) return null;
    switch (pids.first) {
      case 0x00:
        // PID 02 (the VIN) alone, or with the calibration ID (04), its
        // verification number (06) and the ECU's name (0A) for a survey.
        return surveyData
            ? [0x49, 0x00, 0x54, 0x40, 0x00, 0x00]
            : [0x49, 0x00, 0x40, 0x00, 0x00, 0x00];
      case 0x02:
        // One data item, then the 17 characters.
        return [
          0x49,
          0x02,
          0x01,
          ...vin.padRight(17).substring(0, 17).codeUnits,
        ];
      case 0x04 when surveyData:
        return [0x49, 0x04, 0x01, ..._padded(calibrationId, 16)];
      case 0x06 when surveyData:
        return [0x49, 0x06, 0x01, 0x12, 0x34, 0x56, 0x78];
      case 0x0A when surveyData:
        return [0x49, 0x0A, 0x01, ..._padded('ECM-SIM', 20)];
    }
    return null;
  }

  /// [text] as ASCII, cut or padded with zeros to [length] bytes.
  static List<int> _padded(String text, int length) {
    final bytes = text.codeUnits.take(length).toList();
    return [...bytes, ...List<int>.filled(length - bytes.length, 0)];
  }

  // ------------------------------------------------------------------ mode 06

  /// The monitor IDs this ECU has results for: an oxygen sensor monitor, a
  /// catalyst monitor and a misfire monitor (SAE J1979, Mode 06).
  static const List<int> _monitorIds = [0x01, 0x21, 0xA1];

  /// Mode 06: PID 00, 20... are masks of monitor IDs, as in Mode 01; a monitor
  /// ID gives its test results, each a test ID, a unit and scaling ID, the value
  /// and the limits it is held to.
  List<int>? _mode06(List<int> request) {
    if (request.length != 1) return null;
    final id = request.first;
    if (id % 0x20 == 0) {
      final mask = SupportMask.encode(_monitorIds, id);
      if (id != 0 && mask.every((b) => b == 0)) return null;
      return [0x46, id, ...mask];
    }
    if (!_monitorIds.contains(id)) return null;
    List<int> result(int test, int value, int low, int high) => [
      test,
      0x0A,
      ..._word(value),
      ..._word(low),
      ..._word(high),
    ];
    return [
      0x46,
      id,
      ...result(0x80, 0x0100, 0x0000, 0x0400),
      ...result(0x81, 0x0080, 0x0000, 0x0400),
    ];
  }
}
