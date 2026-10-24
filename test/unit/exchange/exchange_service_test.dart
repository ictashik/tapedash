// The exchange service (docs/EXCHANGE.md 3, 6): what an export holds, what an import
// adds and what it leaves alone, that importing twice changes nothing, that two
// devices' trips end up as both, that a bad file changes nothing, and that a setup
// is applied only when asked, and only while parked.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/exchange/crc32.dart';
import 'package:tapedash/exchange/exchange_service.dart';
import 'package:tapedash/exchange/tdx_format.dart';
import 'package:tapedash/insights/rest_voltage_log.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/trips/trip.dart';

import 'tdx_format_test.dart' show fill, samples, trip;

class FakeProfile implements ProfileAccess {
  FakeProfile({Map<String, Object?>? profile})
    : profile = profile ?? {},
      device = {};

  Map<String, Object?> profile;
  Map<String, Object?> device;
  int applied = 0;
  int appliedDevice = 0;

  @override
  Future<Map<String, Object?>> readProfile() async => profile;

  @override
  Future<Map<String, Object?>> readDevice() async => device;

  @override
  Future<List<String>> describeProfile(Map<String, Object?> clean) async => [
    for (final k in clean.keys) 'Would set $k',
  ];

  @override
  Future<void> applyProfile(Map<String, Object?> clean) async {
    applied++;
    profile = {...profile, ...clean};
  }

  @override
  Future<void> applyDevice(Map<String, Object?> clean) async {
    appliedDevice++;
    device = {...device, ...clean};
  }
}

class Side {
  Side({String kind = 'phone', Map<String, Object?>? profile, this.onFills})
    : trips = MemoryTripRepository(),
      fills = MemoryFillUpRepository(),
      profile = FakeProfile(profile: profile),
      rest = RestVoltageLog(
        store: MemoryKeyValueStore(),
        clock: FakeClock()..advance(const Duration(days: 40)),
      ) {
    service = ExchangeService(
      trips: trips,
      fills: fills,
      rest: rest,
      profile: this.profile,
      device: TdxDeviceInfo(id: kind, kind: kind),
      appVersion: '0.9.0',
      onFillUpsChanged: () async => fillsChanged++,
    );
  }

  final MemoryTripRepository trips;
  final MemoryFillUpRepository fills;
  final FakeProfile profile;
  final RestVoltageLog rest;
  final Future<void> Function()? onFills;
  late final ExchangeService service;
  int fillsChanged = 0;

  Future<void> drive(
    int day, {
    int n = 20,
    bool open = false,
    bool demo = false,
  }) async {
    final t = trip(day: day);
    await trips.createWithSamples(
      Trip(
        startedAt: t.startedAt,
        endedAt: open ? null : t.endedAt,
        isDemo: demo,
        distanceKm: t.distanceKm,
        litres: t.litres,
        cost: t.cost,
        pricePerLitre: t.pricePerLitre,
        engineSeconds: t.engineSeconds,
      ),
      samples(n),
    );
  }

  Future<List<int>> export([Set<TdxScope>? scopes]) async {
    final bytes = <int>[];
    await service.export(
      scopes: scopes ?? TdxScope.portable,
      emit: bytes.addAll,
      now: DateTime.utc(2026, 10, 24, 8),
    );
    return bytes;
  }

  Future<ImportReport> import(
    List<int> bytes, {
    ImportOptions options = const ImportOptions(),
  }) => service.import(() => Stream.value(bytes), options: options);
}

Future<List<int>> exportOf(Side s, [Set<TdxScope>? scopes]) => s.export(scopes);

void main() {
  group('an export', () {
    test('holds finished trips oldest first, with their samples', () async {
      final a = Side();
      await a.drive(9);
      await a.drive(2, n: 5);
      await a.drive(5, n: 3);
      final bytes = await a.export();
      final types = [
        for (final l in const LineSplitter().convert(utf8.decode(bytes)))
          (jsonDecode(l) as Map)['t'],
      ];
      expect(types, [
        'tdx',
        'trip',
        'samples',
        'trip',
        'samples',
        'trip',
        'samples',
        'end',
      ]);

      final b = Side();
      final report = await b.import(bytes);
      expect(report.tripsAdded, 3);
      expect(report.samplesAdded, 20 + 5 + 3);
      final order = (await b.trips.all()).map((t) => t.startedAt.day).toList();
      expect(order, [9, 5, 2], reason: 'the repository lists newest first');
    });

    test('leaves out trips that are not finished and simulated ones', () async {
      final a = Side();
      await a.drive(1);
      await a.drive(2, open: true);
      await a.drive(3, demo: true);
      final summary = await a.service.export(
        scopes: {TdxScope.trips},
        emit: (_) {},
        now: DateTime.utc(2026),
      );
      expect(summary.trips, 1);
      expect(summary.sentence, 'Exported 1 trip.');
    });

    test('holds only the scopes asked for', () async {
      final a = Side(
        profile: {
          'money': {'pricePerLitre': 100.0},
        },
      );
      await a.drive(1);
      await a.fills.add(fill);
      final onlyFills = await a.export({TdxScope.fillups});
      final text = utf8.decode(onlyFills);
      expect(text, contains('"t":"fillup"'));
      expect(text, isNot(contains('"t":"trip"')));
      expect(text, isNot(contains('"t":"profile"')));
      expect(text, contains('"scopes":["fillups"]'));
    });

    test('the settings of one screen are in only when asked', () async {
      final a = Side();
      a.profile.device = {
        'hud': {'color': 'amber'},
      };
      expect(utf8.decode(await a.export()), isNot(contains('"t":"device"')));
      expect(
        utf8.decode(await a.export({TdxScope.device})),
        contains('"t":"device"'),
      );
    });

    test('says what it wrote, and says so when there is nothing', () async {
      final a = Side();
      final none = await a.service.export(
        scopes: TdxScope.portable,
        emit: (_) {},
        now: DateTime.utc(2026),
      );
      expect(none.sentence, 'Nothing to export yet.');
      await a.drive(1);
      await a.drive(2);
      await a.fills.add(fill);
      a.profile.profile = {
        'money': {'pricePerLitre': 1.0},
      };
      final all = await a.service.export(
        scopes: TdxScope.portable,
        emit: (_) {},
        now: DateTime.utc(2026),
      );
      expect(all.sentence, 'Exported 2 trips, 1 fill-up, the setup.');
      expect(all.toJson()['operation'], 'export');
      expect(all.bytes, greaterThan(100));
    });
  });

  group('an import', () {
    test(
      'adds trips, fill-ups, readings and the setup it is told to',
      () async {
        final a = Side(
          profile: {
            'money': {'pricePerLitre': 115.0},
          },
        );
        await a.drive(1);
        await a.drive(2);
        await a.fills.add(fill);
        await a.rest.note(12.6);
        final bytes = await a.export();

        final b = Side();
        final report = await b.import(
          bytes,
          options: const ImportOptions(applyProfile: true),
        );
        expect(report.ok, isTrue);
        expect(report.tripsAdded, 2);
        expect(report.fillUpsAdded, 1);
        expect(report.restAdded, 1);
        expect(report.profile, ProfileOutcome.applied);
        expect(b.profile.profile, {
          'money': {'pricePerLitre': 115.0},
        });
        expect((await b.trips.all()).length, 2);
        expect((await b.fills.all()).single.factor, 1.02);
        expect(b.rest.readings.single.volts, 12.6);
        expect(b.fillsChanged, 1, reason: 'the calibration is rebuilt once');
        expect(
          report.sentence,
          'Added 2 trips, 1 fill-up and 1 battery reading. '
          'The setup in the file was applied.',
        );
      },
    );

    test(
      'a trip comes in with a new id, its samples, and not as a simulation',
      () async {
        final a = Side();
        await a.drive(4, n: 12);
        final b = Side();
        await b.drive(8);
        await b.import(await a.export());
        final all = await b.trips.all();
        final added = all.singleWhere((t) => t.startedAt.day == 4);
        expect(added.id, isNotNull);
        expect(added.isDemo, isFalse);
        expect(added.isOpen, isFalse);
        expect((await b.trips.samples(added.id!)).length, 12);
      },
    );

    test(
      'importing the same file twice changes nothing the second time',
      () async {
        final a = Side();
        await a.drive(1);
        await a.drive(2);
        await a.fills.add(fill);
        final bytes = await a.export();
        final b = Side();
        await b.import(bytes);
        final again = await b.import(bytes);
        expect(again.tripsAdded, 0);
        expect(again.tripsSkipped, 2);
        expect(again.fillUpsAdded, 0);
        expect(again.fillUpsSkipped, 1);
        expect(again.sentence, '3 were already here.');
        expect((await b.trips.all()).length, 2);
        expect((await b.fills.all()).length, 1);
        expect(b.fillsChanged, 1);
      },
    );

    test(
      'two devices that drove different trips end up with all of them',
      () async {
        final phone = Side();
        final watch = Side(kind: 'watch');
        await phone.drive(1);
        await phone.drive(2);
        await watch.drive(2);
        await watch.drive(3);
        await watch.import(await phone.export());
        await phone.import(await watch.export());
        for (final side in [phone, watch]) {
          expect((await side.trips.all()).map((t) => t.startedAt.day).toSet(), {
            1,
            2,
            3,
          });
          expect((await side.trips.all()).length, 3);
        }
      },
    );

    test('a trip that is in the file twice is added once', () async {
      final a = Side();
      await a.drive(1);
      final once = utf8.decode(await a.export()).split('\n');
      // Repeat the trip and its samples, and seal the file again.
      final body = [once[0], once[1], once[2], once[1], once[2]];
      final text = '${body.join('\n')}\n';
      final crc = Crc32.of(utf8.encode(text)).toRadixString(16).padLeft(8, '0');
      final bytes = utf8.encode(
        '$text{"t":"end","counts":{"trip":2,"samples":2},"crc32":"$crc"}\n',
      );
      final report = await Side().import(bytes);
      expect(report.tripsAdded, 1);
      expect(report.tripsSkipped, 1);
    });

    test(
      'samples of a trip that was skipped are not given to another',
      () async {
        final a = Side();
        await a.drive(1, n: 6);
        await a.drive(2, n: 9);
        final b = Side();
        await b.drive(1, n: 2);
        await b.import(await a.export());
        final all = await b.trips.all();
        final one = all.singleWhere((t) => t.startedAt.day == 1);
        final two = all.singleWhere((t) => t.startedAt.day == 2);
        expect((await b.trips.samples(one.id!)).length, 2);
        expect((await b.trips.samples(two.id!)).length, 9);
      },
    );

    test('a file that is refused changes nothing, and says why', () async {
      final a = Side();
      await a.drive(1);
      final bytes = await a.export();
      final b = Side();
      await b.drive(7);
      final report = await b.import(bytes.sublist(0, bytes.length - 40));
      expect(report.ok, isFalse);
      expect(report.sentence, startsWith('This file is not complete'));
      expect(report.tripsAdded, 0);
      expect((await b.trips.all()).length, 1);
      expect(b.fillsChanged, 0);
    });

    test('a file that cannot be read at all is refused in words', () async {
      final b = Side();
      final report = await b.service.import(
        () => Stream<List<int>>.error(const FileSystemException('gone')),
      );
      expect(report.ok, isFalse);
      expect(report.sentence, contains('could not be read'));
    });

    test('lines that cannot be used are counted and the rest comes in', () async {
      final a = Side();
      await a.drive(1);
      await a.drive(2);
      final lines = utf8.decode(await a.export()).split('\n');
      // Spoil the first trip's distance, and seal it again with the same counts.
      lines[1] = lines[1].replaceFirst(
        RegExp(r'"distanceKm":[0-9.]+'),
        '"distanceKm":-3',
      );
      final text = '${lines.sublist(0, lines.length - 2).join('\n')}\n';
      final crc = Crc32.of(utf8.encode(text)).toRadixString(16).padLeft(8, '0');
      final footer = utf8.decode(await a.export()).trim().split('\n').last;
      final counts = (jsonDecode(footer) as Map)['counts'];
      final bytes = utf8.encode(
        '$text${jsonEncode({'t': 'end', 'counts': counts, 'crc32': crc})}\n',
      );
      final report = await Side().import(bytes);
      expect(report.rejected, 1);
      expect(report.tripsAdded, 1);
      expect(report.sentence, 'Added 1 trip. 1 line could not be used.');
    });

    test('a dry run counts what would change and changes nothing', () async {
      final a = Side(
        profile: {
          'money': {'pricePerLitre': 100.0},
        },
      );
      await a.drive(1);
      await a.fills.add(fill);
      final bytes = await a.export();
      final b = Side();
      final report = await b.import(
        bytes,
        options: const ImportOptions(applyProfile: true, dryRun: true),
      );
      expect(report.tripsAdded, 1);
      expect(report.fillUpsAdded, 1);
      expect(report.sentence, startsWith('Would add 1 trip and 1 fill-up.'));
      expect((await b.trips.all()), isEmpty);
      expect((await b.fills.all()), isEmpty);
      expect(b.profile.applied, 0);
      expect(b.fillsChanged, 0);
    });

    test('a gzipped file imports the same', () async {
      final a = Side();
      await a.drive(1, n: 400);
      final bytes = gzip.encode(await a.export());
      final report = await Side().import(bytes);
      expect(report.tripsAdded, 1);
      expect(report.samplesAdded, 400);
    });
  });

  group('the setup in a file', () {
    Future<List<int>> withSetup() => Side(
      profile: {
        'money': {'pricePerLitre': 115.0},
        'look': {'livery': 'ember'},
      },
    ).export();

    test('is offered and not applied unless asked', () async {
      final b = Side();
      final report = await b.import(await withSetup());
      expect(report.profile, ProfileOutcome.offered);
      expect(report.profileChanges, ['Would set money', 'Would set look']);
      expect(b.profile.applied, 0);
      expect(report.sentence, contains('has not been applied'));
    });

    test('is applied when asked', () async {
      final b = Side();
      final report = await b.import(
        await withSetup(),
        options: const ImportOptions(applyProfile: true),
      );
      expect(report.profile, ProfileOutcome.applied);
      expect(b.profile.applied, 1);
      expect(b.profile.profile['look'], {'livery': 'ember'});
    });

    test(
      'waits while the car is moving, and the trips still come in',
      () async {
        final a = Side(
          profile: {
            'money': {'pricePerLitre': 99.0},
          },
        );
        await a.drive(1);
        final b = Side();
        final report = await b.import(
          await a.export(),
          options: const ImportOptions(
            applyProfile: true,
            canApplySettings: false,
          ),
        );
        expect(report.profile, ProfileOutcome.deferred);
        expect(b.profile.applied, 0);
        expect(report.tripsAdded, 1);
        expect(report.sentence, contains('waits until the car has stopped'));
      },
    );

    test(
      'the settings of one screen are applied only when asked for, too',
      () async {
        final a = Side();
        a.profile.device = {
          'sound': {'enabled': true},
        };
        final bytes = await a.export({TdxScope.device});
        final b = Side();
        await b.import(bytes, options: const ImportOptions(applyProfile: true));
        expect(b.profile.appliedDevice, 0);
        await b.import(bytes, options: const ImportOptions(applyDevice: true));
        expect(b.profile.appliedDevice, 1);
      },
    );

    test('is checked: what is invalid is not applied', () async {
      final a = Side(
        profile: {
          'vehicle': {'tankL': 9999, 'displacementL': 1.2},
        },
      );
      final b = Side();
      final report = await b.import(
        await a.export(),
        options: const ImportOptions(applyProfile: true),
      );
      expect(b.profile.profile['vehicle'], {'displacementL': 1.2});
      expect(report.profileProblems.single, contains('vehicle.tankL'));
    });
  });

  test('the battery log keeps its newest 120 when a file has more', () async {
    final lots = [
      for (var i = 0; i < 150; i++)
        RestReading(DateTime.utc(2026, 1, 1).add(Duration(days: i)), 12.5),
    ];
    final log = RestVoltageLog(
      store: MemoryKeyValueStore(),
      clock: FakeClock(),
    );
    expect(await log.merge(lots), RestVoltageLog.keep);
    expect(log.readings.length, RestVoltageLog.keep);
    expect(log.readings.last.at, lots.last.at);
    expect(await log.merge(lots), 0, reason: 'the old ones are not new again');
  });

  test('the report is JSON a script can read', () async {
    final a = Side();
    await a.drive(1);
    final report = await Side().import(await a.export());
    final json = jsonDecode(jsonEncode(report.toJson())) as Map;
    expect(json['operation'], 'import');
    expect(json['ok'], isTrue);
    expect(json['tripsAdded'], 1);
    expect(json['sentence'], 'Added 1 trip.');
    expect(json['profile'], 'none');
  });
}
