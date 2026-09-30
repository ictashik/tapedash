import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/platform/fake_device_features.dart';
import 'package:tapedash/platform/file_session_sink.dart';

void main() {
  late Directory temp;
  late FakeDeviceFeatures device;
  late FileSessionSink sink;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tapedash_sink');
    device = FakeDeviceFeatures()..filesDirectory = temp.path;
    sink = FileSessionSink(device);
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
    device.dispose();
  });

  test('a recording is written under recordings/, and reads back', () async {
    final log = const SessionLog(
      header: {'adapter': 'OBDII'},
      entries: [],
    ).format();
    await sink.save('session-1.log', log);
    final file = File('${temp.path}/recordings/session-1.log');
    expect(file.existsSync(), isTrue);
    expect(
      SessionLog.parse(file.readAsStringSync()).header['adapter'],
      'OBDII',
    );
    expect(sink.directory, '${temp.path}/recordings');
  });

  test('saving again replaces it, and no half-written file is left', () async {
    await sink.save('a.log', 'one');
    await sink.save('a.log', 'two, longer');
    expect(
      File('${temp.path}/recordings/a.log').readAsStringSync(),
      'two, longer',
    );
    final names = Directory(
      '${temp.path}/recordings',
    ).listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(names, ['a.log']);
  });

  test('a phone with no folder says so, for the caller to shrug off', () async {
    device.filesDirectory = null;
    await expectLater(
      sink.save('a.log', 'x'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
