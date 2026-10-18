// The insight analyses against the first real drives (recordings/real): a
// Honda City on a cheap BLE adapter. Only what the recordings' own five-second
// "vitals" notes carry (speed, revs, volts and fuel flow), which is coarser than
// the app's one-second trip samples, so these are checks of plausibility, not
// figures. They exist because the analyses were first written against made-up
// drives, and the first real ones found a speed glitch and a CVT.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/insights/gearbox.dart';
import 'package:tapedash/insights/power_curve.dart';
import 'package:tapedash/insights/voltage_trace.dart';
import 'package:tapedash/trips/trip.dart';

double? _num(String? s) => s == null || s == '-' ? null : double.tryParse(s);

List<List<TripSample>> _drives() {
  final dir = Directory('recordings/real');
  if (!dir.existsSync()) return const [];
  final out = <List<TripSample>>[];
  for (final f in dir.listSync().whereType<File>().where(
    (f) => f.path.endsWith('.log'),
  )) {
    final samples = <TripSample>[];
    for (final line in f.readAsLinesSync()) {
      if (!line.contains('@ vitals ')) continue;
      final at = double.tryParse(line.split(' ').first);
      if (at == null) continue;
      final kv = <String, String>{
        for (final p in line.split('@ vitals ').last.split(' '))
          if (p.contains('=')) p.split('=')[0]: p.split('=')[1],
      };
      final kmh = _num(kv['kmh']);
      final rpm = _num(kv['rpm']);
      if (kmh == null || rpm == null) continue;
      samples.add(
        TripSample(
          seconds: at,
          speedKmh: kmh,
          rpm: rpm,
          throttle: 20,
          litresPerHour: _num(kv['lph']) ?? 0,
          voltage: _num(kv['volts']),
        ),
      );
    }
    if (samples.length > 30) out.add(samples);
  }
  return out;
}

void main() {
  final drives = _drives();

  test('there are real drives to check against', () {
    expect(drives.length, greaterThanOrEqualTo(5));
  });

  test('the City is a CVT: its revs make a fan, not gears', () {
    final g = Gearbox.from(drives);
    expect(g.observed, greaterThan(2000));
    expect(g.isFan, isTrue);
  });

  test('its power curve is a small petrol engine\'s, not a glitch\'s', () {
    final c = PowerCurve.from(drives);
    expect(c.isEmpty, isFalse);
    // A 1.5 L makes about 90 PS at the crank; at the wheels in ordinary driving
    // the edge sits well under that, and one wrong speed reading must not move it.
    expect(c.highest!.kw, inInclusiveRange(10, 60));
    expect(c.coveredRpm, lessThan(6500));
  });

  test('its alternator holds about 14 V', () {
    for (final d in drives.take(6)) {
      final v = VoltageTrace.from(d);
      if (v.isEmpty) continue;
      expect(v.median, inInclusiveRange(13.5, 14.6));
      expect(v.chargingShare, greaterThan(0.7));
    }
  });
}
