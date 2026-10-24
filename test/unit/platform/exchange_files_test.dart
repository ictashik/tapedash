// The exchange folder (docs/EXCHANGE.md 4): its three folders, what an import takes
// from the inbox, that an export never overwrites another, that a file read is kept
// in done/, and result.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/platform/exchange_files.dart';
import 'package:tapedash/platform/fake_device_features.dart';

void main() {
  late Directory temp;
  late ExchangeFiles files;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tapedash_exchange_');
    files = ExchangeFiles(rootDirectory: Directory('${temp.path}/exchange'));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('makes outbox, inbox and done where adb will look for them', () async {
    final root = await files.root();
    expect(root!.path, '${temp.path}/exchange');
    for (final sub in ['outbox', 'inbox', 'done']) {
      expect(Directory('${root.path}/$sub').existsSync(), isTrue, reason: sub);
    }
    expect(await files.outboxPath, '${root.path}/outbox');
  });

  test(
    'uses the phone\'s own external files folder, and none if it has none',
    () async {
      final device = FakeDeviceFeatures()
        ..filesDirectory = '${temp.path}/files';
      final onDevice = ExchangeFiles(device: device);
      expect((await onDevice.root())!.path, '${temp.path}/files/exchange');
      expect(
        Directory('${temp.path}/files/exchange/inbox').existsSync(),
        isTrue,
      );

      final none = ExchangeFiles(device: FakeDeviceFeatures());
      expect(await none.root(), isNull);
      expect(await none.inbox(), isEmpty);
      expect(await none.newOutboxFile('x.tdx'), isNull);
      await none.writeResult({'a': 1}); // does nothing, and does not throw
    },
  );

  test('the inbox is the exchange files only, in name order', () async {
    final root = (await files.root())!;
    for (final name in ['b.tdx', 'a.tdx.gz', 'notes.txt', 'c.TDX', 'd.json']) {
      File('${root.path}/inbox/$name').writeAsStringSync('x');
    }
    Directory('${root.path}/inbox/folder.tdx').createSync();
    final names = (await files.inbox()).map((f) => f.uri.pathSegments.last);
    expect(names, ['a.tdx.gz', 'b.tdx', 'c.TDX']);
  });

  test('an export is never written over another of the same name', () async {
    final a = (await files.newOutboxFile('tapedash-all-1.tdx.gz'))!;
    a.writeAsStringSync('first');
    final b = (await files.newOutboxFile('tapedash-all-1.tdx.gz'))!;
    b.writeAsStringSync('second');
    final c = (await files.newOutboxFile('tapedash-all-1.tdx.gz'))!;
    expect(a.uri.pathSegments.last, 'tapedash-all-1.tdx.gz');
    expect(b.uri.pathSegments.last, 'tapedash-all-1-2.tdx.gz');
    expect(c.uri.pathSegments.last, 'tapedash-all-1-3.tdx.gz');
    expect(a.readAsStringSync(), 'first');
  });

  test('a file that has been read is moved to done/, and kept', () async {
    final root = (await files.root())!;
    final f = File('${root.path}/inbox/one.tdx')..writeAsStringSync('data');
    await files.markDone(f);
    expect(f.existsSync(), isFalse);
    expect(File('${root.path}/done/one.tdx').readAsStringSync(), 'data');

    // The same name again does not lose the first.
    final again = File('${root.path}/inbox/one.tdx')..writeAsStringSync('more');
    await files.markDone(again);
    expect(File('${root.path}/done/one.tdx').readAsStringSync(), 'data');
    expect(File('${root.path}/done/one-2.tdx').readAsStringSync(), 'more');
  });

  test(
    'result.json says what the last one did, and is written whole',
    () async {
      await files.writeResult({'operation': 'import', 'ok': true, 'n': 3});
      final root = (await files.root())!;
      final text = File('${root.path}/result.json').readAsStringSync();
      expect(jsonDecode(text), {'operation': 'import', 'ok': true, 'n': 3});
      expect(File('${root.path}/result.json.part').existsSync(), isFalse);
      await files.writeResult({'operation': 'export'});
      expect(jsonDecode(File('${root.path}/result.json').readAsStringSync()), {
        'operation': 'export',
      });
    },
  );

  test('a file is named for what, when and where it was made', () {
    final at = DateTime(2026, 10, 24, 8, 5, 9);
    expect(
      ExchangeFiles.fileName(what: 'all', at: at, kind: 'watch', gzip: true),
      'tapedash-all-20261024-080509-watch.tdx.gz',
    );
    expect(
      ExchangeFiles.fileName(
        what: 'profile',
        at: at,
        kind: 'phone',
        gzip: false,
      ),
      'tapedash-profile-20261024-080509-phone.tdx',
    );
  });
}
