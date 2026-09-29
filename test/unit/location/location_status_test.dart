import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/location/location_source.dart';
import 'package:tapedash/location/location_status.dart';

class _Source implements LocationSource {
  // Closed by each test's tear-down.
  // ignore: close_sinks
  final StreamController<LocationFix> c = StreamController.broadcast(
    sync: true,
  );
  @override
  Stream<LocationFix> get fixes => c.stream;
  @override
  bool get isRunning => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

LocationFix fix(double accuracy) => LocationFix(
  latitude: 12,
  longitude: 77,
  speedMs: 5,
  headingDegrees: 90,
  altitudeM: 900,
  accuracyM: accuracy,
  time: DateTime(2026),
);

void main() {
  test('a good fix is a fix, and it falls to no after a few quiet seconds', () {
    final clock = FakeClock();
    final source = _Source();
    addTearDown(source.c.close);
    final status = LocationStatus(source: source, scheduler: clock);
    addTearDown(status.dispose);
    expect(status.hasFix.value, isFalse);
    source.c.add(fix(5));
    expect(status.hasFix.value, isTrue);
    clock.advance(const Duration(seconds: 3));
    expect(status.hasFix.value, isTrue);
    clock.advance(const Duration(seconds: 2));
    expect(status.hasFix.value, isFalse);
  });

  test('each fix renews it', () {
    final clock = FakeClock();
    final source = _Source();
    addTearDown(source.c.close);
    final status = LocationStatus(source: source, scheduler: clock);
    addTearDown(status.dispose);
    for (var i = 0; i < 10; i++) {
      source.c.add(fix(5));
      clock.advance(const Duration(seconds: 2));
    }
    expect(status.hasFix.value, isTrue);
  });

  test('a poor fix is not a fix', () {
    final clock = FakeClock();
    final source = _Source();
    addTearDown(source.c.close);
    final status = LocationStatus(source: source, scheduler: clock);
    addTearDown(status.dispose);
    source.c.add(fix(120));
    expect(status.hasFix.value, isFalse);
    expect(status.last.value!.accuracyM, 120);
  });

  test('a poor fix after a good one takes it away at once', () {
    final clock = FakeClock();
    final source = _Source();
    addTearDown(source.c.close);
    final status = LocationStatus(source: source, scheduler: clock);
    addTearDown(status.dispose);
    source.c.add(fix(5));
    source.c.add(fix(200));
    expect(status.hasFix.value, isFalse);
  });
}
