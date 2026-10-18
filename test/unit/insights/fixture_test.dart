import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/insights/cold_start.dart';
import 'package:tapedash/insights/ghost_commute.dart';
import 'package:tapedash/insights/powerflow.dart';
import 'package:tapedash/insights/voltage_trace.dart';

import '../../support/insight_fixture.dart';

void main() {
  // The analyses against a whole made-up life of driving, not a hand-made
  // trace: the numbers in the made-up commute have to come out as a person would
  // expect, or the captures of the pages mean nothing.
  final data = madeInsightData(year: true);

  test('a commute is a believable drive', () {
    final c = madeCommute(id: 1, start: DateTime(2026, 10, 1, 8));
    expect(c.trip.distanceKm, closeTo(12, 1.5));
    expect(c.samples.length, inInclusiveRange(1000, 1800));
    expect(c.trip.litres / c.trip.distanceKm, closeTo(0.09, 0.04));
    expect(c.trip.idleSeconds, greaterThan(120));
    expect(c.trip.cost, closeTo(c.trip.litres * 115, 1e-9));
  });

  test('its gearbox shows the gears a city drive uses, a CVT\'s a fan', () {
    expect(data.gearbox.isFan, isFalse);
    expect(data.gearbox.gears, inInclusiveRange(4, 5));
    final cvt = madeInsightData(manual: false);
    expect(cvt.gearbox.isFan, isTrue);
  });

  test('its toll map finds the big junction first', () {
    final top = data.tollMap.spots.first;
    expect(top.seconds, greaterThan(300));
    expect(top.stops, greaterThanOrEqualTo(4));
  });

  test('its cold starts cost more than its warm running', () {
    final t = data.trips.firstWhere((t) => t.startedAt.hour == 8);
    final c = data.coldStartOf(t)!;
    expect(c.extraRupees, greaterThan(3));
    expect(c.warmAtMinutes, inInclusiveRange(4, 14));
    expect(ColdStart.coldBelowC, 65);
  });

  test('its voltage dips and its powerflow adds up', () {
    final t = data.trips.first;
    final v = VoltageTrace.from(data.samplesOf(t));
    expect(v.dips, isNotEmpty);
    expect(v.chargingShare, greaterThan(0.6));
    final f = data.powerflowOf(t)!;
    expect(f.wheelShare, inInclusiveRange(0.05, Powerflow.ceiling));
    expect(f.brakeShare, greaterThan(0.05));
  });

  test('its mornings match each other, not the evenings', () {
    final newest = data.trips.firstWhere((t) => t.startedAt.hour == 8);
    final m = data.ghostOf(newest)!;
    expect(m.before.startedAt.hour, 8);
    expect(GhostMatch.points, 24);
  });

  test('its year has a bar a trip', () {
    final y = data.year(2026);
    expect(y.trips, greaterThan(250));
    expect(y.spent, greaterThan(20000));
  });
}
