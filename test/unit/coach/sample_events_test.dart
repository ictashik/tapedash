import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/sample_events.dart';
import 'package:tapedash/trips/trip.dart';

TripSample s(double t, double kmh, {double throttle = 20, double rpm = 2000}) =>
    TripSample(
      seconds: t,
      speedKmh: kmh,
      rpm: rpm,
      throttle: throttle,
      litresPerHour: 3,
    );

void main() {
  test('a hard acceleration is marked where it starts, once', () {
    final samples = [
      for (var t = 0; t < 4; t++) s(t.toDouble(), 30),
      // 3.6 km/h a second is 1 m/s2; 12 a second is 3.3 m/s2.
      for (var t = 4; t < 8; t++) s(t.toDouble(), 30 + 12.0 * (t - 3)),
      for (var t = 8; t < 12; t++) s(t.toDouble(), 78),
    ];
    final e = SampleEvents.find(samples);
    expect([for (final x in e) x.type], [SampleEventType.hardAcceleration]);
    expect(e.single.index, 4);
  });

  test('hard braking likewise', () {
    final samples = [
      for (var t = 0; t < 3; t++) s(t.toDouble(), 80),
      // 20 km/h a second is 5.6 m/s2.
      for (var t = 3; t < 7; t++) s(t.toDouble(), 80 - 20.0 * (t - 2)),
      for (var t = 7; t < 9; t++) s(t.toDouble(), 0),
    ];
    final e = SampleEvents.find(samples);
    expect(e.map((x) => x.type), [SampleEventType.hardBraking]);
  });

  test('an open throttle at speed is a hard acceleration too', () {
    final samples = [
      for (var t = 0; t < 6; t++) s(t.toDouble(), 50, throttle: 90),
    ];
    expect(SampleEvents.find(samples).map((x) => x.type), [
      SampleEventType.hardAcceleration,
    ]);
  });

  test(
    'a minute stopped with the engine on is a long idle, marked at its start',
    () {
      final samples = [
        s(0, 20),
        s(1, 15),
        s(2, 10),
        s(3, 5),
        for (var t = 4; t < 80; t++) s(t.toDouble(), 0, rpm: 800),
        s(80, 5),
        s(81, 10),
        s(82, 15),
        s(83, 20),
      ];
      final e = SampleEvents.find(samples);
      expect(e.map((x) => x.type), [SampleEventType.longIdle]);
      expect(e.single.index, 4);
    },
  );

  test('a short stop is not', () {
    final samples = [
      s(0, 20),
      s(1, 15),
      s(2, 10),
      s(3, 5),
      for (var t = 4; t < 30; t++) s(t.toDouble(), 0, rpm: 800),
      s(30, 5),
      s(31, 10),
      s(32, 15),
    ];
    expect(SampleEvents.find(samples), isEmpty);
  });

  test('a gap in the samples ends what was open', () {
    final samples = [
      s(0, 30),
      s(1, 30),
      for (var t = 100; t < 105; t++) s(t.toDouble(), 30),
    ];
    expect(SampleEvents.find(samples), isEmpty);
  });

  test('a gentle drive has none', () {
    final samples = [
      // A triangle wave between 20 and 50 km/h, 1 km/h a second.
      for (var t = 0; t < 120; t++)
        s(t.toDouble(), 20 + (t % 60 < 30 ? t % 60 : 60 - t % 60).toDouble()),
    ];
    expect(SampleEvents.find(samples), isEmpty);
  });
}
