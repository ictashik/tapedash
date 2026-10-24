// The exchange file's format (docs/EXCHANGE.md 1, 2): the checksum, what a writer
// writes and a reader reads back, and everything a reader must refuse: a file cut
// short, damaged, from a newer version, or not ours; and the lines it must take
// one by one.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/exchange/crc32.dart';
import 'package:tapedash/exchange/tdx_codec.dart';
import 'package:tapedash/exchange/tdx_format.dart';
import 'package:tapedash/exchange/tdx_profile.dart';
import 'package:tapedash/exchange/tdx_reader.dart';
import 'package:tapedash/exchange/tdx_writer.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/insights/rest_voltage_log.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/trip.dart';

const device = TdxDeviceInfo(id: 'abc123', kind: 'watch', name: 'Test Watch');
final created = DateTime.utc(2026, 10, 24, 8, 15);

Trip trip({int day = 1, double km = 14.2, int hours = 1}) => Trip(
  startedAt: DateTime.utc(2026, 10, day, 8),
  endedAt: DateTime.utc(2026, 10, day, 8 + hours),
  distanceKm: km,
  litres: 0.93,
  uncalibratedLitres: 0.89,
  cost: 106.9,
  pricePerLitre: 115,
  idleSeconds: 142,
  engineSeconds: 1800,
  bucketLitres: {
    SpendBucket.normal: 0.71,
    SpendBucket.idling: 0.08,
    SpendBucket.hardAcceleration: 0.06,
    SpendBucket.highSpeed: 0.08,
  },
  blockBuckets: [
    SpendBucket.normal,
    SpendBucket.normal,
    SpendBucket.idling,
    SpendBucket.hardAcceleration,
    SpendBucket.highSpeed,
  ],
  fuelSource: FuelSource.airFlow,
  lowConfidence: true,
  calibrationFactor: 1.04,
  hardAccelerations: 2,
  hardBrakings: 1,
  longIdles: 1,
  longestIdleSeconds: 96,
  highRpmSeconds: 4,
  speedingSeconds: 0,
);

List<TripSample> samples(int n) => [
  for (var i = 0; i < n; i++)
    TripSample(
      seconds: i.toDouble(),
      speedKmh: (i % 60).toDouble(),
      rpm: 800 + (i % 50) * 20,
      throttle: (i % 30).toDouble(),
      litresPerHour: 0.7 + (i % 10) / 10,
      latitude: i.isEven ? 12.9716 + i * 1e-5 : null,
      longitude: i.isEven ? 77.5946 + i * 1e-5 : null,
      load: i % 7 == 0 ? null : 30,
      coolantC: 80,
      voltage: 14.1,
    ),
];

final fill = FillUp(
  at: DateTime.utc(2026, 10, 20),
  litres: 31.2,
  amount: 3588,
  fullTank: true,
  factor: 1.02,
);

/// A whole file, from the writer.
List<int> build({
  Set<TdxScope> scopes = TdxScope.portable,
  Map<String, Object?>? profile,
  List<(Trip, List<TripSample>)> trips = const [],
  List<FillUp> fills = const [],
  List<RestReading> rest = const [],
}) {
  final bytes = <int>[];
  final w = TdxWriter(bytes.addAll)
    ..header(
      appVersion: '0.9.0',
      created: created,
      device: device,
      scopes: scopes,
    );
  if (profile != null) w.profile(profile);
  for (final (t, s) in trips) {
    w.trip(t, s);
  }
  for (final f in fills) {
    w.fillUp(f);
  }
  if (rest.isNotEmpty) w.rest(rest);
  w.finish();
  return bytes;
}

Stream<List<int>> stream(List<int> bytes, {int chunk = 4096}) async* {
  for (var i = 0; i < bytes.length; i += chunk) {
    yield bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk);
  }
}

Future<List<TdxRecord>> read(List<int> bytes, {int chunk = 4096}) =>
    TdxReader.records(stream(bytes, chunk: chunk)).toList();

Future<String> refusal(List<int> bytes) async {
  try {
    await TdxReader.scan(stream(bytes));
  } on TdxException catch (e) {
    return e.message;
  }
  fail('the file was not refused');
}

/// Lines of a file, as text, without the footer.
List<String> lines(List<int> bytes) =>
    const LineSplitter().convert(utf8.decode(bytes));

/// A file made of [body] lines and a footer that is right about them.
List<int> sealed(List<String> body, {Map<String, int>? counts}) {
  final text = '${body.join('\n')}\n';
  final crc = Crc32.of(utf8.encode(text));
  final footer = jsonEncode({
    't': 'end',
    'counts': counts ?? <String, int>{},
    'crc32': crc.toRadixString(16).padLeft(8, '0'),
  });
  return utf8.encode('$text$footer\n');
}

const header =
    '{"t":"tdx","v":1,"app":"tapedash","appVersion":"0","createdMs":1793088900000,'
    '"device":{"id":"x","kind":"phone"},"scopes":["trips"]}';

void main() {
  group('the checksum', () {
    test('is the CRC-32 of the standard check string', () {
      expect(Crc32.of(utf8.encode('123456789')), 0xCBF43926);
      expect(Crc32.of(const []), 0);
      expect((Crc32()..add(utf8.encode('123456789'))).hex, 'cbf43926');
    });

    test('is the same however the bytes are cut up', () {
      final bytes = utf8.encode('a line\nand another line\n' * 50);
      final whole = Crc32.of(bytes);
      final parts = Crc32()
        ..add(bytes.sublist(0, 7))
        ..add(bytes.sublist(7, 333))
        ..add(bytes.sublist(333));
      expect(parts.value, whole);
    });

    test('matches gzip\'s own, which uses the same polynomial', () {
      final bytes = utf8.encode('The exchange file ' * 40);
      final gz = gzip.encode(bytes);
      // The last eight bytes of a gzip member are the CRC-32 and the size,
      // little-endian.
      final tail = ByteData.sublistView(Uint8List.fromList(gz), gz.length - 8);
      expect(Crc32.of(bytes), tail.getUint32(0, Endian.little));
    });
  });

  group('writing', () {
    test('a header first, a footer last, one JSON object a line', () {
      final all = lines(build(trips: [(trip(), samples(3))], fills: [fill]));
      expect(jsonDecode(all.first), containsPair('t', 'tdx'));
      expect(jsonDecode(all.first), containsPair('v', 1));
      expect(jsonDecode(all.last), containsPair('t', 'end'));
      for (final l in all) {
        expect(jsonDecode(l), isA<Map<String, Object?>>());
      }
      expect(all.map((l) => (jsonDecode(l) as Map)['t']), [
        'tdx',
        'trip',
        'samples',
        'fillup',
        'end',
      ]);
    });

    test('the footer counts what was written and carries the checksum', () {
      final bytes = build(
        profile: {
          'money': {'pricePerLitre': 115.0},
        },
        trips: [(trip(), samples(5)), (trip(day: 2), samples(5))],
        fills: [fill],
        rest: [RestReading(DateTime.utc(2026, 10, 20), 12.6)],
      );
      final all = lines(bytes);
      final footer = jsonDecode(all.last) as Map<String, Object?>;
      expect(footer['counts'], {
        'profile': 1,
        'trip': 2,
        'samples': 2,
        'fillup': 1,
        'rest': 1,
      });
      final body = utf8.encode(
        '${all.sublist(0, all.length - 1).join('\n')}\n',
      );
      expect(footer['crc32'], Crc32.of(body).toRadixString(16).padLeft(8, '0'));
    });

    test('samples are cut into lines of 2,000 rows', () {
      final all = lines(build(trips: [(trip(), samples(4500))]));
      final cuts = [
        for (final l in all)
          if ((jsonDecode(l) as Map)['t'] == 'samples')
            ((jsonDecode(l) as Map)['rows'] as List).length,
      ];
      expect(cuts, [2000, 2000, 500]);
    });

    test('a number that is not finite is written as null, not as NaN', () {
      final t = trip();
      final bad = TripSample(
        seconds: 0,
        speedKmh: 5,
        rpm: 900,
        throttle: 3,
        litresPerHour: double.nan,
        load: double.infinity,
      );
      final text = utf8.decode(
        build(
          trips: [
            (t, [bad]),
          ],
        ),
      );
      expect(text, isNot(contains('NaN')));
      expect(text, isNot(contains('Infinity')));
    });

    test('is in order: no record before the header, none after the footer', () {
      final w = TdxWriter((_) {});
      expect(() => w.fillUp(fill), throwsStateError);
      w.header(
        appVersion: '1',
        created: created,
        device: device,
        scopes: const {},
      );
      expect(
        () => w.header(
          appVersion: '1',
          created: created,
          device: device,
          scopes: const {},
        ),
        throwsStateError,
      );
      w.finish();
      expect(() => w.fillUp(fill), throwsStateError);
    });
  });

  group('a round trip', () {
    final original = trip();
    final rows = samples(2500);

    test(
      'gives back the trip, its samples, the fill-up and the readings',
      () async {
        final bytes = build(
          trips: [(original, rows)],
          fills: [fill],
          rest: [
            RestReading(DateTime.utc(2026, 10, 20, 7), 12.61),
            RestReading(DateTime.utc(2026, 10, 21, 7), 12.58),
          ],
          profile: {
            'vehicle': {'fuelType': 'petrol', 'displacementL': 1.5},
          },
        );
        final records = await read(bytes);

        final t = records.whereType<TdxTripRecord>().single;
        expect(t.key, original.startedAt.millisecondsSinceEpoch);
        expect(
          t.trip.endedAt!.millisecondsSinceEpoch,
          original.endedAt!.millisecondsSinceEpoch,
        );
        expect(t.trip.distanceKm, 14.2);
        expect(t.trip.litres, 0.93);
        expect(t.trip.uncalibratedLitres, 0.89);
        expect(t.trip.cost, 106.9);
        expect(t.trip.pricePerLitre, 115);
        expect(t.trip.idleSeconds, 142);
        expect(t.trip.engineSeconds, 1800);
        expect(t.trip.bucketLitres[SpendBucket.idling], 0.08);
        expect(t.trip.blockBuckets, original.blockBuckets);
        expect(t.trip.fuelSource, FuelSource.airFlow);
        expect(t.trip.lowConfidence, isTrue);
        expect(t.trip.calibrationFactor, 1.04);
        expect(t.trip.hardAccelerations, 2);
        expect(t.trip.hardBrakings, 1);
        expect(t.trip.longIdles, 1);
        expect(t.trip.longestIdleSeconds, 96);
        expect(t.trip.highRpmSeconds, 4);
        expect(t.trip.speedingSeconds, 0);
        expect(t.trip.isDemo, isFalse);
        expect(t.trip.isOpen, isFalse);

        final back = [
          for (final s in records.whereType<TdxSamplesRecord>()) ...s.samples,
        ];
        expect(back.length, rows.length);
        for (final i in [0, 1, 7, 1999, 2000, 2499]) {
          expect(back[i].seconds, rows[i].seconds);
          expect(back[i].speedKmh, rows[i].speedKmh);
          expect(back[i].rpm, rows[i].rpm);
          expect(back[i].throttle, rows[i].throttle);
          expect(back[i].litresPerHour, rows[i].litresPerHour);
          expect(back[i].latitude, rows[i].latitude);
          expect(back[i].longitude, rows[i].longitude);
          expect(back[i].load, rows[i].load);
          expect(back[i].coolantC, rows[i].coolantC);
          expect(back[i].voltage, rows[i].voltage);
        }

        final f = records.whereType<TdxFillUpRecord>().single.fillUp;
        expect(f.at.millisecondsSinceEpoch, fill.at.millisecondsSinceEpoch);
        expect(f.litres, 31.2);
        expect(f.amount, 3588);
        expect(f.fullTank, isTrue);
        expect(f.factor, 1.02);

        final r = records.whereType<TdxRestRecord>().single.readings;
        expect(r.map((e) => e.volts), [12.61, 12.58]);

        final p = records.whereType<TdxProfileRecord>().single.clean;
        expect(p.values['vehicle'], {
          'fuelType': 'petrol',
          'displacementL': 1.5,
        });

        final h = records.first as TdxHeaderRecord;
        expect(h.version, 1);
        expect(h.device.kind, 'watch');
        expect(h.device.name, 'Test Watch');
        expect(
          h.created,
          created.toLocal().isUtc ? created : created.toLocal(),
        );
        expect(h.scopes, TdxScope.portable);
        expect(records.last, isA<TdxEndRecord>());
      },
    );

    test(
      'is the same however the bytes arrive, even a byte at a time',
      () async {
        final bytes = build(trips: [(original, samples(30))], fills: [fill]);
        final whole = await read(bytes);
        final bytewise = await read(bytes, chunk: 1);
        expect(bytewise.length, whole.length);
        expect(
          bytewise.whereType<TdxSamplesRecord>().single.samples.length,
          30,
        );
      },
    );

    test(
      'a trip with no price keeps no price, and no samples is no samples',
      () async {
        final t = Trip(
          startedAt: DateTime.utc(2026, 10, 3, 9),
          endedAt: DateTime.utc(2026, 10, 3, 9, 20),
          distanceKm: 2,
          litres: 0.1,
        );
        final records = await read(build(trips: [(t, const [])]));
        final back = records.whereType<TdxTripRecord>().single.trip;
        expect(back.cost, isNull);
        expect(back.pricePerLitre, isNull);
        expect(back.fuelSource, FuelSource.none);
        expect(records.whereType<TdxSamplesRecord>(), isEmpty);
      },
    );

    test('a gzipped file reads the same as a plain one', () async {
      final plain = build(trips: [(original, samples(300))], fills: [fill]);
      final zipped = gzip.encode(plain);
      expect(zipped.length, lessThan(plain.length));
      final a = await read(plain);
      final b = await read(zipped, chunk: 17);
      expect(b.length, a.length);
      expect((await TdxReader.scan(stream(zipped))).counts, {
        'trip': 1,
        'samples': 1,
        'fillup': 1,
      });
    });
  });

  group('a file that cannot be used is refused whole, in words', () {
    final good = build(
      trips: [(trip(), samples(40)), (trip(day: 2), samples(40))],
      fills: [fill],
    );

    test('one cut short at any line, or in the middle of one', () async {
      final text = utf8.decode(good);
      final ls = text.split('\n');
      // Cut after each line but the last (the footer), and mid-line.
      for (var n = 1; n < ls.length - 1; n++) {
        final cut = utf8.encode('${ls.sublist(0, n).join('\n')}\n');
        expect(
          await refusal(cut),
          startsWith('This file is not complete'),
          reason: 'cut after line $n',
        );
      }
      for (final at in [10, 100, good.length ~/ 2, good.length - 3]) {
        expect(
          await refusal(good.sublist(0, at)),
          startsWith('This file is not complete'),
          reason: 'cut at byte $at',
        );
      }
    });

    test('one with a digit changed, though still valid JSON', () async {
      final text = utf8
          .decode(good)
          .replaceFirst('"distanceKm":14.2', '"distanceKm":14.3');
      expect(text, isNot(utf8.decode(good)));
      expect(
        await refusal(utf8.encode(text)),
        contains('checksum does not match'),
      );
    });

    test('one with a record taken out or put in', () async {
      final ls = lines(good);
      final without = [...ls]..removeAt(3);
      expect(
        await refusal(utf8.encode('${without.join('\n')}\n')),
        contains('checksum does not match'),
      );
    });

    test('one with no footer, and one with a footer that is not one', () async {
      final noFooter = utf8.encode('$header\n');
      expect(await refusal(noFooter), startsWith('This file is not complete'));
      final badFooter = utf8.encode('$header\n{"t":"end","counts":{}}\n');
      expect(await refusal(badFooter), contains('checksum'));
    });

    test(
      'one whose footer is right about the bytes and wrong about the lines',
      () async {
        final bytes = sealed([header], counts: {'trip': 3});
        expect(await refusal(bytes), contains('says it holds 3 trip lines'));
      },
    );

    test('one with anything after the footer', () async {
      expect(
        await refusal([...good, ...utf8.encode('{"t":"trip"}\n')]),
        contains('more after the end'),
      );
      // Blank lines after it are only blank lines.
      expect(
        (await TdxReader.scan(stream([...good, 0x0A, 0x0A]))).lines,
        greaterThan(0),
      );
    });

    test('one made by a newer version', () async {
      final newer = sealed([header.replaceFirst('"v":1', '"v":2')]);
      expect(await refusal(newer), contains('newer TapeDash'));
      expect(await refusal(newer), contains('version 2'));
    });

    test('one that is not ours', () async {
      expect(await refusal(utf8.encode('hello\n')), contains('not a TapeDash'));
      expect(
        await refusal(utf8.encode('{"a":1}\n')),
        contains('not a TapeDash'),
      );
      expect(await refusal(utf8.encode('[1,2]\n')), contains('not a TapeDash'));
      expect(
        await refusal(utf8.encode('{"t":"trip"}\n')),
        contains('not a TapeDash'),
      );
      expect(
        await refusal(utf8.encode('{"t":"tdx","v":"one"}\n')),
        contains('not a TapeDash'),
      );
      expect(await refusal(const []), contains('empty'));
      expect(await refusal(Uint8List(300)), contains('not a TapeDash'));
    });

    test('a gzip file that stops half way', () async {
      final zipped = gzip.encode(good);
      expect(
        await refusal(zipped.sublist(0, zipped.length ~/ 2)),
        startsWith('This file is not complete'),
      );
    });

    test('a line that is far too long', () async {
      final huge = utf8.encode('$header\n${'x' * (Tdx.maxLineBytes + 10)}\n');
      expect(await refusal(huge), contains('far too long'));
    });
  });

  group('lines are taken one by one', () {
    Future<TdxScan> scanOf(List<String> body, {Map<String, int>? counts}) =>
        TdxReader.scan(stream(sealed([header, ...body], counts: counts)));

    test(
      'a line of a type from a later version is left alone, and counted',
      () async {
        final scan = await scanOf(['{"t":"hologram","x":1}']);
        expect(scan.ignored, 1);
        expect(scan.rejected, 0);
      },
    );

    test('an unknown field on a known line is ignored', () async {
      final t = Map<String, Object?>.from(TdxCodec.tripToJson(trip()))
        ..['someday'] = {'a': 1};
      final scan = await scanOf([jsonEncode(t)], counts: {'trip': 1});
      expect(scan.counts['trip'], 1);
      expect(scan.rejected, 0);
    });

    test('a line that is not JSON is rejected on its own', () async {
      final scan = await scanOf(
        ['this is not json', jsonEncode(TdxCodec.tripToJson(trip()))],
        counts: {'trip': 1},
      );
      expect(scan.rejected, 1);
      expect(scan.rejections.single, startsWith('line 2: '));
      expect(scan.counts['trip'], 1);
    });

    test('a second header is rejected', () async {
      final scan = await scanOf([header]);
      expect(scan.rejected, 1);
    });

    final cases = <String, Map<String, Object?> Function(Map<String, Object?>)>{
      'a negative distance': (j) => j..['distanceKm'] = -5,
      'a trip that ends before it starts': (j) =>
          j..['endedMs'] = (j['startedMs']! as int) - 1000,
      'a trip that is not finished': (j) => j..['endedMs'] = null,
      'a trip that lasts a week': (j) =>
          j..['endedMs'] = (j['startedMs']! as int) + 7 * 24 * 3600 * 1000,
      'a trip in 1970': (j) => j
        ..['startedMs'] = 5000
        ..['k'] = 5000
        ..['endedMs'] = 9000,
      'a price of ₹100,000 a litre': (j) => j..['pricePerLitre'] = 100000,
      'fuel of a million litres': (j) => j..['litres'] = 1e6,
      'a block the Money Tape does not have': (j) => j..['blocks'] = 'nnzn',
      'a coach count that is not a number': (j) => j..['hardBrakings'] = 'many',
      'a bucket out of range': (j) =>
          j..['bucketLitres'] = {'normal': -1, 'idling': 0},
    };
    for (final c in cases.entries) {
      test('${c.key} is rejected, and the rest of the file goes on', () async {
        final bad = c.value(
          Map<String, Object?>.from(TdxCodec.tripToJson(trip())),
        );
        final scan = await scanOf(
          [jsonEncode(bad), jsonEncode(TdxCodec.tripToJson(trip(day: 9)))],
          counts: {'trip': 2},
        );
        expect(scan.rejected, 1, reason: c.key);
        expect(scan.rejections.single, startsWith('line 2: '));
        expect(
          scan.firstTrip!.millisecondsSinceEpoch,
          trip(day: 9).startedAt.millisecondsSinceEpoch,
        );
      });
    }

    test('only the first five reasons are kept', () async {
      final bad = jsonEncode(
        Map<String, Object?>.from(TdxCodec.tripToJson(trip()))
          ..['distanceKm'] = -1,
      );
      final scan = await scanOf(List.filled(9, bad), counts: {'trip': 9});
      expect(scan.rejected, 9);
      expect(scan.rejections.length, 5);
    });

    test('a bad sample row is dropped and the rest of the line kept', () async {
      final line = jsonEncode({
        't': 'samples',
        'trip': 1,
        'cols': ['s', 'kmh', 'rpm', 'thr', 'lph', 'lat', 'lon'],
        'rows': [
          [0, 10, 900, 5, 1.0, 12.9, 77.5],
          [1, 999, 900, 5, 1.0, null, null],
          [2, 12, 900, 5, 1.0, 400, 77.5],
          [3, 12, 900, 5],
          [4, 14, 1000, 9, 1.2, null, null],
          'junk',
        ],
      });
      final records = await read(
        sealed([header, line], counts: {'samples': 1}),
      );
      final s = records.whereType<TdxSamplesRecord>().single;
      expect(s.samples.map((e) => e.seconds), [0, 4]);
      expect(s.dropped, 4);
    });

    test(
      'samples may carry their columns in any order, and fewer of them',
      () async {
        final line = jsonEncode({
          't': 'samples',
          'trip': 1,
          'cols': ['rpm', 's', 'lph', 'kmh', 'thr', 'v'],
          'rows': [
            [900, 0, 1.0, 10, 5, 14.2],
          ],
        });
        final records = await read(
          sealed([header, line], counts: {'samples': 1}),
        );
        final s = records.whereType<TdxSamplesRecord>().single.samples.single;
        expect(s.rpm, 900);
        expect(s.speedKmh, 10);
        expect(s.voltage, 14.2);
        expect(s.latitude, isNull);
      },
    );

    test(
      'samples with no speed column are rejected, with the column named',
      () async {
        final line = jsonEncode({
          't': 'samples',
          'trip': 1,
          'cols': ['s', 'rpm'],
          'rows': [
            [0, 900],
          ],
        });
        final scan = await TdxReader.scan(
          stream(sealed([header, line], counts: {'samples': 1})),
        );
        expect(scan.rejections.single, contains('"kmh"'));
      },
    );

    test(
      'a fill-up of nothing, or from before there were cars, is rejected',
      () async {
        final a = jsonEncode(TdxCodec.fillUpToJson(fill)..['litres'] = 0);
        final b = jsonEncode(
          TdxCodec.fillUpToJson(fill)
            ..['atMs'] = 1000
            ..['k'] = 1000,
        );
        final scan = await scanOf([a, b], counts: {'fillup': 2});
        expect(scan.rejected, 2);
      },
    );

    test(
      'resting voltages out of range are left out, not the whole line',
      () async {
        final line = jsonEncode({
          't': 'rest',
          'readings': [
            [1793088900000, 12.6],
            [1793088900001, 99],
            [5, 12.6],
            'x',
            [1793088900002, 12.4],
          ],
        });
        final records = await read(sealed([header, line], counts: {'rest': 1}));
        expect(
          records.whereType<TdxRestRecord>().single.readings.map(
            (r) => r.volts,
          ),
          [12.6, 12.4],
        );
      },
    );

    test('the profile\'s problems are kept, line by line', () async {
      final line = jsonEncode({
        't': 'profile',
        'vehicle': {'fuelType': 'steam', 'displacementL': 1.5},
        'money': {'pricePerLitre': -3},
      });
      final scan = await scanOf([line], counts: {'profile': 1});
      expect(scan.profileProblems, hasLength(2));
      expect(scan.profileProblems.first, contains('vehicle.fuelType'));
      expect(scan.profileProblems.last, contains('money.pricePerLitre'));
    });
  });

  group('the profile', () {
    test('keeps what is valid and says why it dropped the rest', () {
      final c = TdxProfile.cleanProfile({
        'vehicle': {
          'fuelType': 'diesel',
          'displacementL': 2.0,
          'tankL': 9999,
          'blend': 'e85',
          'wheels': 4,
        },
        'money': {'pricePerLitre': 115.5, 'currency': 'INR'},
        'adapter': {
          'kind': 'wifi',
          'address': '192.168.0.10',
          'port': 35000,
          'name': 'WiFi ELM',
        },
        'source': 'obd',
        'coach': {'preset': 'sporty', 'speedLimitKmh': 120},
        'look': {
          'livery': 'mono',
          'driverSide': 'left',
          'cluster': 2,
          'ignition': 'subtle',
          'reduceMotion': true,
        },
        'unknownSection': {'a': 1},
      });
      expect(c.values['vehicle'], {'fuelType': 'diesel', 'displacementL': 2.0});
      expect(c.values['money'], {'pricePerLitre': 115.5, 'currency': 'INR'});
      expect(c.values['adapter'], {
        'kind': 'wifi',
        'address': '192.168.0.10',
        'name': 'WiFi ELM',
        'port': 35000,
      });
      expect(c.values['source'], 'obd');
      expect(c.values['coach'], {'preset': 'sporty', 'speedLimitKmh': 120.0});
      expect((c.values['look']! as Map)['livery'], 'mono');
      expect(c.values.containsKey('unknownSection'), isFalse);
      expect(c.problems, [
        'vehicle.tankL is not a number from 5 to 200',
        'vehicle.blend is not one of e0, e10, e20',
      ]);
    });

    test('an adapter with no address is no adapter', () {
      final c = TdxProfile.cleanProfile({
        'adapter': {'kind': 'ble', 'address': ''},
      });
      expect(c.values.containsKey('adapter'), isFalse);
      expect(c.problems.single, contains('no kind or no address'));
    });

    test('a part that is missing stays missing, and nothing is invented', () {
      final c = TdxProfile.cleanProfile({
        'money': {'pricePerLitre': 100},
      });
      expect(c.values, {
        'money': {'pricePerLitre': 100.0},
      });
      expect(TdxProfile.cleanProfile(<String, Object?>{}).isEmpty, isTrue);
      expect(TdxProfile.cleanProfile('nonsense').problems, isNotEmpty);
    });

    test('the settings of one screen are checked the same way', () {
      final c = TdxProfile.cleanDevice({
        'hud': {
          'color': 'amber',
          'flipH': true,
          'flipV': false,
          'position': 0.25,
          'scale': 9,
        },
        'tier': 'lite',
        'mode': 'night',
        'sound': {'enabled': true, 'volume': 0.5, 'profile': 'v8'},
        'compatibility': true,
        'recordSessions': 'yes',
      });
      expect(c.values['hud'], {
        'color': 'amber',
        'flipH': true,
        'flipV': false,
        'position': 0.25,
      });
      expect(c.values['tier'], 'lite');
      expect(c.values['mode'], 'night');
      expect(c.values['sound'], {
        'enabled': true,
        'profile': 'v8',
        'volume': 0.5,
      });
      expect(c.values['compatibility'], true);
      expect(c.values.containsKey('recordSessions'), isFalse);
      expect(c.problems, [
        'hud.scale is not a number from 0.6 to 1.4',
        'recordSessions is not true or false',
      ]);
    });
  });

  test('the scopes have names, and a default export is the portable ones', () {
    expect(TdxScope.named('trips'), TdxScope.trips);
    expect(TdxScope.named('nope'), isNull);
    expect(TdxScope.portable, isNot(contains(TdxScope.device)));
    expect(TdxScope.portable, contains(TdxScope.profile));
  });
}
