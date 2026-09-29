// The efficiency curve and the sweet spot (CLAUDE.md 8.9): steady samples only,
// 10 km/h bands, and no figure until a band has 3 km.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/efficiency_curve.dart';
import 'package:tapedash/trips/trip.dart';

/// [seconds] seconds at a steady [kmh] burning [lph], one sample a second.
List<TripSample> steady(
  double kmh,
  double lph,
  int seconds, {
  double t0 = 0,
  double throttle = 25,
}) => [
  for (var i = 0; i < seconds; i++)
    TripSample(
      seconds: t0 + i,
      speedKmh: kmh,
      rpm: 2000,
      throttle: throttle,
      litresPerHour: lph,
    ),
];

void main() {
  test('a steady 60 km/h burning 4 L/h does 15 km/L', () {
    // 3 km at 60 km/h is 180 s.
    final curve = SweetSpot.fromTrips([steady(60, 4, 200)]);
    final band = curve.bands.single;
    expect(band.fromKmh, 60);
    expect(band.toKmh, 70);
    expect(band.kmPerLitre, closeTo(15, 0.1));
  });

  test('a band under 3 km reports nothing', () {
    final curve = SweetSpot.fromTrips([steady(60, 4, 120)]);
    expect(curve.bands.single.km, lessThan(3));
    expect(curve.bands.single.kmPerLitre, isNull);
    expect(curve.best, isNull);
  });

  test('the sweet spot is the best of the bands that report', () {
    final curve = SweetSpot.fromTrips([
      steady(40, 3.5, 400),
      steady(65, 3.6, 300),
      steady(95, 6.5, 200),
      steady(110, 9, 30), // too little to report, however good it looks.
    ]);
    expect(curve.reported.map((b) => b.fromKmh), [40, 60, 90]);
    expect(curve.best!.fromKmh, 60);
  });

  test('acceleration and braking are not steady', () {
    final samples = [
      for (var i = 0; i < 200; i++)
        TripSample(
          seconds: i.toDouble(),
          // 3.6 km/h a second is 1 m/s2.
          speedKmh: 20 + 3.6 * (i % 20),
          rpm: 3000,
          throttle: 50,
          litresPerHour: 8,
        ),
    ];
    expect(SweetSpot.fromTrips([samples]).bands, isEmpty);
  });

  test('a throttle that is moving is not steady either', () {
    final samples = [
      for (var i = 0; i < 300; i++)
        TripSample(
          seconds: i.toDouble(),
          speedKmh: 60,
          rpm: 2000,
          throttle: 20 + 8.0 * (i % 2),
          litresPerHour: 4,
        ),
    ];
    expect(SweetSpot.fromTrips([samples]).bands, isEmpty);
  });

  test('a stop is not a band', () {
    expect(SweetSpot.fromTrips([steady(2, 0.8, 600)]).bands, isEmpty);
  });

  test('samples of several trips add up', () {
    final curve = SweetSpot.fromTrips([steady(60, 4, 100), steady(60, 4, 100)]);
    expect(curve.bands.single.km, closeTo(200 * 60 / 3600, 0.05));
    expect(curve.bands.single.kmPerLitre, isNotNull);
  });

  test('a gap in the samples is not bridged', () {
    final samples = [...steady(60, 4, 50), ...steady(60, 4, 50, t0: 500)];
    final band = SweetSpot.fromTrips([samples]).bands.single;
    // 98 one-second stretches, not 550 s.
    expect(band.km, closeTo(98 * 60 / 3600, 0.02));
  });

  test('sweetSpotFrom reads the real trips, and not the demo ones', () async {
    final repo = MemoryTripRepository();
    final real = await repo.create(Trip(startedAt: DateTime(2026, 3, 1)));
    await repo.addSamples(real.id!, steady(60, 4, 200));
    final demo = await repo.create(
      Trip(startedAt: DateTime(2026, 3, 2), isDemo: true),
    );
    await repo.addSamples(demo.id!, steady(90, 6, 200));
    final curve = await sweetSpotFrom(repo);
    expect(curve.bands.map((b) => b.fromKmh), [60]);
  });
}
