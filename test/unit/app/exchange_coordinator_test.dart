// The exchange coordinator (docs/EXCHANGE.md 4 to 6): an export into the outbox, an
// import from the inbox that keeps what it read, what adb asks at the launch, a
// setup that waits while the car moves, and the calibration rebuilt from fill-ups
// that came in. Two devices, each with its own folder, one file carried between.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/exchange_coordinator.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/exchange/tdx_format.dart';
import 'package:tapedash/money/calibration.dart';
import 'package:tapedash/platform/exchange_files.dart';
import 'package:tapedash/platform/exchange_host.dart';

import '../exchange/tdx_format_test.dart' show fill, samples, trip;

class Device {
  Device._(this.app, this.dir, this.host, this.exchange);

  static Future<Device> make(String kind, {FakeExchangeHost? host}) async {
    final app = await AppServices.memory();
    final dir = Directory.systemTemp.createTempSync('tapedash_$kind');
    final h = host ?? FakeExchangeHost();
    final exchange = ExchangeCoordinator(
      app: app,
      files: ExchangeFiles(rootDirectory: Directory('${dir.path}/exchange')),
      host: h,
      clock: FakeClock()..advance(const Duration(days: 20000)),
      installId: kind,
      deviceKind: kind,
      deviceName: 'Test $kind',
      appVersion: '0.9.0',
    );
    return Device._(app, dir, h, exchange);
  }

  final AppServices app;
  final Directory dir;
  final FakeExchangeHost host;
  final ExchangeCoordinator exchange;

  Directory get inbox => Directory('${dir.path}/exchange/inbox');
  Directory get outbox => Directory('${dir.path}/exchange/outbox');
  Directory get done => Directory('${dir.path}/exchange/done');

  Future<void> drive(int day) async {
    final t = trip(day: day);
    await app.trips.createWithSamples(t, samples(10));
  }

  /// The first file in the outbox.
  File get exported => outbox.listSync().whereType<File>().first;

  void dispose() {
    exchange.dispose();
    dir.deleteSync(recursive: true);
  }
}

void main() {
  late Device watch;
  late Device phone;

  setUp(() async {
    watch = await Device.make('watch');
    phone = await Device.make('phone');
  });

  tearDown(() {
    watch.dispose();
    phone.dispose();
  });

  /// What the watch exported, as it would arrive by adb.
  Future<void> carry({bool apply = false}) async {
    await watch.exchange.exportAll();
    await phone.exchange.refresh();
    final f = watch.exported;
    await phone.exchange.files.root();
    f.copySync('${phone.inbox.path}/${f.uri.pathSegments.last}');
  }

  group('an export', () {
    test('writes a compressed file to the outbox and says where', () async {
      await watch.drive(1);
      await watch.drive(2);
      final summary = await watch.exchange.exportAll();
      expect(summary!.trips, 2);
      final files = watch.outbox.listSync();
      expect(files, hasLength(1));
      expect(files.single.path, endsWith('-watch.tdx.gz'));
      expect(files.single.path, contains('tapedash-all-'));
      final s = watch.exchange.status.value;
      expect(s.ok, isTrue);
      expect(
        s.sentence,
        'Exported 2 trips, the setup. Saved in the outbox folder.',
      );
      expect(s.outboxPath, files.single.path);
      expect(s.busy, isFalse);
      // The file is gzip, and the folder says what it did for a script.
      expect(File(files.single.path).readAsBytesSync().take(2), [0x1F, 0x8B]);
      expect(
        File('${watch.dir.path}/exchange/result.json').readAsStringSync(),
        contains('"operation": "export"'),
      );
    });

    test('a file with no trips in it is plain text', () async {
      await watch.app.money.setPrice(101);
      await watch.exchange.exportAll(scopes: {TdxScope.profile});
      expect(watch.exported.path, endsWith('-watch.tdx'));
      expect(watch.exported.readAsStringSync(), startsWith('{"t":"tdx"'));
      expect(watch.exported.path, contains('tapedash-profile-'));
    });

    test('with nothing to say, leaves no file about', () async {
      // The setup is always something; ask only for trips of a car with none.
      final summary = await watch.exchange.exportAll(scopes: {TdxScope.trips});
      expect(summary!.trips, 0);
      expect(watch.outbox.listSync(), isEmpty);
      expect(watch.exchange.status.value.sentence, 'Nothing to export yet.');
    });

    test('hands the file to the share sheet when there is one', () async {
      await phone.drive(1);
      phone.host.canShare = true;
      await phone.exchange.exportAll(share: true);
      expect(phone.host.shared, [phone.exported.path]);
      expect(
        phone.exchange.status.value.sentence,
        'Exported 1 trip, the setup.',
      );
    });

    test('and says where it is when there is not', () async {
      await watch.drive(1);
      await watch.exchange.exportAll(share: true);
      expect(watch.host.shared, isEmpty);
      expect(watch.exchange.status.value.sentence, endsWith('outbox folder.'));
    });

    test('a device with nowhere to write says so', () async {
      final bare = ExchangeCoordinator(
        app: watch.app,
        files: ExchangeFiles(),
        host: FakeExchangeHost(),
        clock: FakeClock(),
        installId: 'x',
        deviceKind: 'watch',
        deviceName: '',
        appVersion: '0',
      );
      await bare.exportAll();
      expect(bare.status.value.ok, isFalse);
      expect(bare.status.value.sentence, contains('nowhere to write'));
      expect(bare.status.value.busy, isFalse);
    });
  });

  group('an import from the inbox', () {
    test('adds what is new, keeps the file in done/, and says so', () async {
      await watch.drive(1);
      await watch.drive(2);
      await watch.app.fills.add(fill);
      await carry();
      expect(
        phone.exchange.status.value.inboxFiles,
        0,
        reason: 'not counted yet',
      );
      await phone.exchange.refresh();
      expect(phone.exchange.status.value.inboxFiles, 1);

      final before = phone.exchange.changes.value;
      final reports = await phone.exchange.importInbox();
      expect(reports.single.tripsAdded, 2);
      expect((await phone.app.trips.all()).length, 2);
      expect((await phone.app.fills.all()).length, 1);
      expect(phone.inbox.listSync(), isEmpty);
      expect(phone.done.listSync(), hasLength(1));
      expect(
        phone.exchange.status.value.sentence,
        'Added 2 trips and 1 fill-up. '
        'The file has a setup, and it has not been applied.',
      );
      expect(phone.exchange.status.value.inboxFiles, 0);
      expect(
        phone.exchange.changes.value,
        before + 1,
        reason: 'screens re-read',
      );
      expect(
        File('${phone.dir.path}/exchange/result.json').readAsStringSync(),
        contains('"tripsAdded": 2'),
      );
    });

    test('the calibration is rebuilt from the fill-ups that came in', () async {
      await watch.app.fills.add(fill); // a full tank with a factor of 1.02
      await carry();
      expect(
        phone.app.ledger.confidence.value,
        CalibrationConfidence.uncalibrated,
      );
      await phone.exchange.importInbox();
      expect(
        phone.app.ledger.confidence.value,
        CalibrationConfidence.calibrating,
      );
      expect(phone.app.ledger.calibration.factor, closeTo(1.02, 1e-9));
      // And once only: reading the fill-ups again does not count them twice.
      await phone.app.ledger.rebuild();
      expect(phone.app.ledger.calibration.factors, [1.02]);
    });

    test('a file that is refused stays in the inbox, and says why', () async {
      await watch.drive(1);
      await carry();
      final f = phone.inbox.listSync().whereType<File>().single;
      final bytes = f.readAsBytesSync();
      f.writeAsBytesSync(bytes.sublist(0, bytes.length - 12));
      await phone.exchange.importInbox();
      expect(phone.inbox.listSync(), hasLength(1));
      expect(phone.done.listSync(), isEmpty);
      final s = phone.exchange.status.value;
      expect(s.ok, isFalse);
      expect(s.sentence, startsWith('This file is not complete'));
      expect((await phone.app.trips.all()), isEmpty);
    });

    test('an empty inbox is said, not an error', () async {
      expect(await phone.exchange.importInbox(), isEmpty);
      expect(
        phone.exchange.status.value.sentence,
        'There is nothing in the inbox folder.',
      );
      expect(phone.exchange.status.value.ok, isTrue);
    });

    test('the same file twice adds nothing the second time', () async {
      await watch.drive(1);
      await carry();
      final saved = phone.inbox
          .listSync()
          .whereType<File>()
          .single
          .readAsBytesSync();
      await phone.exchange.importInbox();
      File('${phone.inbox.path}/again.tdx.gz').writeAsBytesSync(saved);
      await phone.exchange.importInbox();
      expect(
        phone.exchange.status.value.sentence,
        '1 was already here. The file has a setup, and it has not been applied.',
      );
      expect((await phone.app.trips.all()).length, 1);
    });
  });

  group('the setup in a file', () {
    Future<void> watchWithSetup() async {
      await watch.app.money.setPrice(120.5);
      await watch.drive(1);
      await carry();
    }

    test(
      'is offered, with what it would change, and applied on a tap',
      () async {
        await watchWithSetup();
        await phone.exchange.importInbox();
        var s = phone.exchange.status.value;
        expect(s.offered, contains('Price: 120.5 a litre'));
        expect(phone.app.money.price.value, isNull);
        await phone.exchange.applyOffered();
        expect(phone.app.money.price.value, 120.5);
        s = phone.exchange.status.value;
        expect(s.sentence, 'The setup was applied.');
        expect(s.offered, isEmpty);
      },
    );

    test(
      'is applied at once when asked, and not while the car moves',
      () async {
        await watchWithSetup();
        phone.exchange.moving.value = true;
        await phone.exchange.importInbox(applyProfile: true);
        expect(phone.app.money.price.value, isNull);
        expect(
          phone.exchange.status.value.sentence,
          contains('waits until the car has stopped'),
        );
        expect(
          (await phone.app.trips.all()).length,
          1,
          reason: 'trips come in',
        );

        await phone.exchange.applyOffered();
        expect(phone.app.money.price.value, isNull, reason: 'still moving');
        phone.exchange.moving.value = false;
        await phone.exchange.applyOffered();
        expect(phone.app.money.price.value, 120.5);
      },
    );
  });

  group('a file the phone\'s picker gave', () {
    test('is read, and the copy in the cache removed', () async {
      await watch.drive(1);
      await watch.exchange.exportAll();
      final picked = File('${phone.dir.path}/picked.tdx.gz')
        ..writeAsBytesSync(watch.exported.readAsBytesSync());
      phone.host
        ..canPick = true
        ..picked = picked.path;
      final report = await phone.exchange.importPicked();
      expect(report!.tripsAdded, 1);
      expect(picked.existsSync(), isFalse);
    });

    test('cancelled, it is nothing', () async {
      phone.host.canPick = true;
      expect(await phone.exchange.importPicked(), isNull);
    });
  });

  group('what adb asks at the launch', () {
    test('an export, of the scopes named', () async {
      await watch.drive(1);
      await watch.app.fills.add(fill);
      watch.host.request = const ExchangeRequest(
        operation: 'export',
        scopes: {TdxScope.fillups},
      );
      await watch.exchange.checkRequest();
      expect(
        watch.outbox.listSync().single.path,
        contains('tapedash-fillups-'),
      );
      expect(
        watch.exchange.status.value.sentence,
        startsWith('Exported 1 fill-up'),
      );
      // Taken once: asking again does nothing.
      await watch.exchange.checkRequest();
      expect(watch.outbox.listSync(), hasLength(1));
    });

    test('an import, which applies the setup only when told to', () async {
      await watch.app.money.setPrice(99.0);
      await watch.drive(1);
      await carry();
      phone.host.request = const ExchangeRequest(operation: 'import');
      await phone.exchange.checkRequest();
      expect(phone.app.money.price.value, isNull);
      expect((await phone.app.trips.all()).length, 1);

      await carry();
      File('${phone.done.path}/x').createSync();
      for (final f in phone.inbox.listSync().whereType<File>()) {
        expect(f.existsSync(), isTrue);
      }
      phone.host.request = const ExchangeRequest(
        operation: 'import',
        applyProfile: true,
      );
      await phone.exchange.checkRequest();
      expect(phone.app.money.price.value, 99.0);
    });

    test('nothing asked, nothing done', () async {
      // The app's first start makes the folders, so that adb has somewhere to push.
      await watch.exchange.refresh();
      expect(watch.inbox.existsSync(), isTrue);
      await watch.exchange.checkRequest();
      expect(watch.outbox.listSync(), isEmpty);
      expect(watch.exchange.status.value.sentence, isNull);
    });
  });

  test('says what the device is called in the files it makes', () async {
    watch.exchange.nameDevice('Galaxy Watch4 Classic');
    await watch.drive(1);
    await watch.exchange.exportAll();
    final out = Process.runSync('gzip', ['-dc', watch.exported.path]);
    expect(out.stdout, contains('"name":"Galaxy Watch4 Classic"'));
    expect(out.stdout, contains('"kind":"watch"'));
    expect(out.stdout, contains('"id":"watch"'));
  });
}
