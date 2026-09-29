import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/fuel/fuel_integrator.dart';

FuelFlow flow(double lph, double seconds) => FuelFlow(
  litresPerHour: lph,
  source: FuelSource.airFlow,
  at: Duration(milliseconds: (seconds * 1000).round()),
  receivedAt: Duration(milliseconds: (seconds * 1000).round()),
);

void main() {
  test('the first estimate opens a stretch and adds nothing', () {
    final i = FuelIntegrator();
    expect(i.add(flow(6, 0)), isNull);
    expect(i.litres, 0);
  });

  test('the rate between two estimates is their average', () {
    final i = FuelIntegrator()..add(flow(6, 0));
    final inc = i.add(flow(12, 1))!;
    expect(inc.litres, closeTo(9 / 3600, 1e-12));
    expect(i.litres, closeTo(9 / 3600, 1e-12));
  });

  test('an hour at 6 L/h is 6 litres', () {
    final i = FuelIntegrator(maxGap: const Duration(hours: 2));
    for (var s = 0; s <= 3600; s += 1) {
      i.add(flow(6, s.toDouble()));
    }
    expect(i.litres, closeTo(6, 1e-9));
  });

  test('a stretch over the longest gap is not integrated', () {
    final i = FuelIntegrator()..add(flow(6, 0));
    final inc = i.add(flow(6, 45))!;
    expect(inc.litres, 0);
    expect(inc.filledGap, isTrue);
    expect(i.litres, 0);
  });

  test('a gap longer than usual but within reason is filled and flagged', () {
    final i = FuelIntegrator()..add(flow(6, 0));
    final inc = i.add(flow(6, 10))!;
    expect(inc.litres, closeTo(6 * 10 / 3600, 1e-12));
    expect(inc.filledGap, isTrue);
  });

  test('an estimate not after the last is ignored', () {
    final i = FuelIntegrator()..add(flow(6, 5));
    expect(i.add(flow(60, 4)), isNull);
    expect(i.add(flow(60, 5)), isNull);
    expect(i.litres, 0);
  });

  test('breakStretch keeps the total and skips the time between', () {
    final i = FuelIntegrator()
      ..add(flow(6, 0))
      ..add(flow(6, 1));
    final before = i.litres;
    i.breakStretch();
    expect(i.add(flow(6, 300)), isNull);
    expect(i.litres, before);
  });
}
