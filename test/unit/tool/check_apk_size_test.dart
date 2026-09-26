// The size budget is a hard rule (CLAUDE.md 3), so its check is tested too.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _script = '${Directory.current.path}/tool/check_apk_size.sh';

const _mb = 1000000;

/// A throwaway project whose APKs have the given sizes in bytes. The files are
/// sparse, so a 20 MB APK costs nothing to create.
Future<ProcessResult> _run({int? v7a, int? arm64, int? x86}) async {
  final root = Directory.systemTemp.createTempSync('tapedash_apk_size_test_');
  addTearDown(() => root.deleteSync(recursive: true));

  void apk(String abi, int? size) {
    if (size == null) return;
    final file = File(
      '${root.path}/build/app/outputs/flutter-apk/app-$abi-release.apk',
    )..createSync(recursive: true);
    final handle = file.openSync(mode: FileMode.write)..truncateSync(size);
    handle.closeSync();
  }

  apk('armeabi-v7a', v7a);
  apk('arm64-v8a', arm64);
  apk('x86_64', x86);
  return Process.run('bash', [_script, '--root', root.path]);
}

extension on ProcessResult {
  String get err => this.stderr as String;
  String get out => this.stdout as String;
}

void main() {
  test('passes when both ABIs are under 20 MB', () async {
    final result = await _run(v7a: 11 * _mb, arm64: 14 * _mb);

    expect(result.exitCode, 0, reason: result.err);
    expect(result.out, contains('armeabi-v7a: 11.0 MB'));
    expect(result.out, contains('arm64-v8a: 14.0 MB'));
    expect(result.out, contains('APK size check passed.'));
  });

  test('one byte under the budget passes', () async {
    final result = await _run(v7a: 20 * _mb - 1, arm64: 1 * _mb);

    expect(result.exitCode, 0, reason: result.err);
  });

  test('exactly 20 MB fails: the budget is "under"', () async {
    final result = await _run(v7a: 1 * _mb, arm64: 20 * _mb);

    expect(result.exitCode, 1);
    expect(
      result.err,
      contains('arm64-v8a: 20.0 MB is not under the 20 MB budget'),
    );
  });

  test('names the ABI that is too big', () async {
    final result = await _run(v7a: 25 * _mb, arm64: 14 * _mb);

    expect(result.exitCode, 1);
    expect(result.err, contains('armeabi-v7a'));
    expect(result.err, isNot(contains('arm64-v8a: ')));
  });

  test('reports every ABI that is too big', () async {
    final result = await _run(v7a: 25 * _mb, arm64: 30 * _mb);

    expect(result.exitCode, 1);
    expect(result.err, contains('armeabi-v7a: 25.0 MB'));
    expect(result.err, contains('arm64-v8a: 30.0 MB'));
  });

  test('a missing armeabi-v7a APK fails: it is never dropped', () async {
    final result = await _run(arm64: 14 * _mb);

    expect(result.exitCode, 1);
    expect(result.err, contains('app-armeabi-v7a-release.apk is missing'));
  });

  test('a missing arm64-v8a APK fails', () async {
    final result = await _run(v7a: 11 * _mb);

    expect(result.exitCode, 1);
    expect(result.err, contains('app-arm64-v8a-release.apk is missing'));
  });

  test('an APK for an ABI we do not ship is ignored', () async {
    final result = await _run(v7a: 11 * _mb, arm64: 14 * _mb, x86: 60 * _mb);

    expect(result.exitCode, 0, reason: result.err);
  });

  test('unknown options are rejected', () async {
    final result = await Process.run('bash', [_script, '--nope']);

    expect(result.exitCode, 2);
  });
}
