// The replay of a trip on Review (DESIGN.md 6.12): frames of a drive round a city
// block, at 640x360 and 720x360, heading up and north up. Skipped unless
// TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/sample_events.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_library.dart';
import 'package:tapedash/ui/design/components/controls/tape_square_button.dart';
import 'package:tapedash/ui/design/components/route_zoom_buttons.dart';
import 'package:tapedash/ui/design/components/trip_transport.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/review/review_page.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../support/harness.dart';

/// A drive along a route with corners and two stops, one sample a second.
List<TripSample> cityDrive() {
  // Waypoints in metres east and north of the start.
  const way = [
    (0.0, 0.0),
    (700.0, 0.0),
    (700.0, 450.0),
    (1300.0, 450.0),
    (1300.0, -200.0),
    (1900.0, -200.0),
    (1900.0, 300.0),
    (2500.0, 300.0),
  ];
  final legs = <double>[];
  for (var i = 1; i < way.length; i++) {
    legs.add(
      math.sqrt(
        math.pow(way[i].$1 - way[i - 1].$1, 2) +
            math.pow(way[i].$2 - way[i - 1].$2, 2),
      ),
    );
  }
  final total = legs.fold<double>(0, (a, b) => a + b);
  (double, double) at(double d) {
    var run = d;
    for (var i = 0; i < legs.length; i++) {
      if (run <= legs[i]) {
        final f = run / legs[i];
        return (
          way[i].$1 + (way[i + 1].$1 - way[i].$1) * f,
          way[i].$2 + (way[i + 1].$2 - way[i].$2) * f,
        );
      }
      run -= legs[i];
    }
    return way.last;
  }

  final out = <TripSample>[];
  var d = 0.0;
  var v = 0.0; // m/s
  var stop = 0;
  for (var t = 0; t < 400 && d < total - 1; t++) {
    // Slow for the corners, stop at two signals, otherwise cruise at 50 km/h.
    var target = 50 / 3.6;
    var near = 99999.0;
    var run = 0.0;
    for (final leg in legs) {
      run += leg;
      near = math.min(near, (run - d).abs());
    }
    if (near < 60) target = 18 / 3.6;
    if ((d - 1250).abs() < 25 || (d - 2350).abs() < 25) {
      if (stop < 14) {
        target = 0;
        if (v < 0.3) stop++;
      }
    }
    final accel = (target - v).clamp(-3.5, 2.4);
    v = math.max(0, v + accel);
    d += v;
    final p = at(d);
    const lat0 = 12.97, lon0 = 77.59;
    final kmh = v * 3.6;
    out.add(
      TripSample(
        seconds: t.toDouble(),
        speedKmh: kmh,
        rpm: 850 + kmh * 34 + (accel > 1 ? 600 : 0),
        throttle: math.max(0, 6 + accel * 14 + kmh * 0.2),
        litresPerHour: 0.9 + kmh * 0.05 + math.max(0, accel) * 1.4,
        latitude: lat0 + p.$2 / 111320,
        longitude: lon0 + p.$1 / (111320 * math.cos(lat0 * math.pi / 180)),
        load: 18 + kmh * 0.4,
        coolantC: 84 + t * 0.01,
        voltage: 14.0,
      ),
    );
  }
  return out;
}

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  for (final size in const [Size(720, 360), Size(640, 360)]) {
    testWidgets('a replay at ${size.width.toInt()}x360', (tester) async {
      setWindow(tester, size);
      final kit = TapeRenderKit();
      addTearDown(kit.dispose);
      final motion = ManualMotionClock();
      addTearDown(motion.dispose);
      final repo = MemoryTripRepository();
      final library = TripLibrary(repo);
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      final samples = cityDrive();
      await tester.runAsync(() async {
        final trip = await repo.create(
          Trip(
            startedAt: DateTime(2026, 3, 10, 9),
            endedAt: DateTime(2026, 3, 10, 9, 7),
            distanceKm: 2.5,
            litres: 0.22,
            cost: 25.3,
            pricePerLitre: 115,
            idleSeconds: 28,
            engineSeconds: samples.length.toDouble(),
            bucketLitres: {
              SpendBucket.normal: 0.17,
              SpendBucket.idling: 0.02,
              SpendBucket.hardAcceleration: 0.03,
              SpendBucket.highSpeed: 0,
            },
          ),
        );
        await repo.addSamples(trip.id!, samples);
        await library.refresh();
      });
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: ReviewPage(
            library: library,
            mode: mode,
            width: size.width,
            height: size.height,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      Future<void> run(double seconds) async {
        for (var t = 0.0; t < seconds; t += 0.05) {
          motion.advance(const Duration(milliseconds: 50), step: 0.05);
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      final tag = '${size.width.toInt()}';
      await run(1);
      await capturePng(tester, 'replay-$tag-0-before');

      await tester.tap(
        find
            .descendant(
              of: find.byType(TripTransport),
              matching: find.byType(TapeSquareButton),
            )
            .at(0),
      );
      await tester.pump();
      await run(2);
      await capturePng(tester, 'replay-$tag-1-start');
      await run(28);
      await capturePng(tester, 'replay-$tag-2-moving');
      await run(40);
      await capturePng(tester, 'replay-$tag-3-later');
      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      // The first marked moment, and the map turned north up.
      final event = SampleEvents.find(samples).first;
      state.player!.seekToSample(event.index.toDouble());
      await run(1);
      await capturePng(tester, 'replay-$tag-3b-event');
      await tester.tap(
        find
            .descendant(
              of: find.byType(RouteZoomButtons),
              matching: find.byType(TapeSquareButton),
            )
            .first,
      );
      await run(3);
      await capturePng(tester, 'replay-$tag-3c-northup');
      state.player!.seekTo(state.player!.duration - 3);
      await run(4);
      await capturePng(tester, 'replay-$tag-4-end');
    }, skip: !enabled);
  }
}
