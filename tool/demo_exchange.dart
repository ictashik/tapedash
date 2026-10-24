// Makes an exchange file to try a watch or a phone with, on an emulator or a bench
// (docs/DEV_SETUP.md, "A watch emulator"): a setup that points the app at
// `tool/sim_server.dart` on the host (10.0.2.2:35000, which an emulator reaches),
// with a price, and eight invented trips with their samples and two fill-ups. The
// trips are made up and say "demo"; nothing here is a real drive.
//
//   dart run tool/demo_exchange.dart demo.tdx.gz [livery]
//   tool/adb_exchange.sh push demo.tdx.gz && tool/adb_exchange.sh import --apply
import 'dart:io';
import 'dart:math' as math;

import 'package:tapedash/exchange/tdx_format.dart';
import 'package:tapedash/exchange/tdx_writer.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/trip.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/demo_exchange.dart <out.tdx.gz> [livery]',
    );
    exit(64);
  }
  final out = File(args.first);
  final livery = args.length > 1 ? args[1] : 'ion';
  final sink = out.openWrite();
  final zip = gzip.encoder.startChunkedConversion(_S(sink));
  final w = TdxWriter(zip.add)
    ..header(
      appVersion: 'demo',
      created: DateTime.utc(2026, 10, 24, 9),
      device: const TdxDeviceInfo(
        id: 'demo',
        kind: 'phone',
        name: 'Pixel (demo)',
      ),
      scopes: TdxScope.portable,
    )
    ..profile({
      'vehicle': {
        'fuelType': 'petrol',
        'displacementL': 1.5,
        'tankL': 40.0,
        'blend': 'e20',
      },
      'money': {'pricePerLitre': 115.0, 'currency': 'INR'},
      'adapter': {
        'kind': 'wifi',
        'address': '10.0.2.2',
        'port': 35000,
        'name': 'Simulated ELM327',
      },
      'source': 'obd',
      'coach': {'preset': 'normal', 'speedLimitKmh': 100},
      'look': {
        'livery': livery,
        'driverSide': 'right',
        'cluster': 0,
        'ignition': 'full',
        'reduceMotion': false,
      },
    });
  final rnd = math.Random(7);
  for (var d = 0; d < 8; d++) {
    final start = DateTime.utc(2026, 10, 14 + d, 3, 30 + rnd.nextInt(20));
    final km = 6 + rnd.nextDouble() * 14;
    final litres = km / (13 + rnd.nextDouble() * 4);
    final secs = (km / (22 + rnd.nextDouble() * 12) * 3600).round();
    final idle = 60.0 + rnd.nextInt(300);
    final blocks = <SpendBucket>[
      for (var i = 0; i < (litres * 115).round(); i++)
        i % 11 == 3
            ? SpendBucket.idling
            : i % 17 == 5
            ? SpendBucket.hardAcceleration
            : SpendBucket.normal,
    ];
    final trip = Trip(
      startedAt: start,
      endedAt: start.add(Duration(seconds: secs)),
      distanceKm: km,
      litres: litres,
      uncalibratedLitres: litres * .97,
      cost: litres * 115,
      pricePerLitre: 115,
      idleSeconds: idle,
      engineSeconds: secs.toDouble(),
      bucketLitres: {
        SpendBucket.normal: litres * .8,
        SpendBucket.idling: litres * .1,
        SpendBucket.hardAcceleration: litres * .06,
        SpendBucket.highSpeed: litres * .04,
      },
      blockBuckets: blocks,
      fuelSource: FuelSource.airFlow,
      hardAccelerations: rnd.nextInt(4),
      hardBrakings: rnd.nextInt(3),
    );
    final samples = [
      for (var s = 0; s < secs; s += 5)
        TripSample(
          seconds: s.toDouble(),
          speedKmh: 20 + 30 * math.sin(s / 90).abs(),
          rpm: 1400 + 800 * math.sin(s / 70).abs(),
          throttle: 12 + 10 * math.sin(s / 50).abs(),
          litresPerHour: 2 + math.sin(s / 60).abs() * 3,
          latitude: 12.9716 + math.sin(s / 400) * .01 + d * 1e-4,
          longitude: 77.5946 + s / 40000,
        ),
    ];
    w.trip(trip, samples);
  }
  w
    ..fillUp(
      FillUp(
        at: DateTime.utc(2026, 10, 10),
        litres: 28.4,
        amount: 3266,
        fullTank: true,
      ),
    )
    ..fillUp(
      FillUp(
        at: DateTime.utc(2026, 10, 18),
        litres: 31.2,
        amount: 3588,
        fullTank: true,
        factor: 1.02,
      ),
    )
    ..finish();
  zip.close();
  sink.close();
}

class _S implements Sink<List<int>> {
  _S(this.s);
  final IOSink s;
  @override
  void add(List<int> d) => s.add(d);
  @override
  void close() {}
}
