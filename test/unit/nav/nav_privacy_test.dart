// Nothing Google Maps says reaches storage (CLAUDE.md 4, "Navigation
// notification"): not a trip, a recording, the exchange file, the settings or a
// log. The navigation feed is read, shown, and let go of.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/nav_service.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/platform/nav_channel.dart';

import '../../support/nav_fixtures.dart';

/// A [KeyValueStore] that keeps every string it was ever given, to look through.
class _Recording extends MemoryKeyValueStore {
  final List<String> written = [];

  @override
  Future<void> setString(String key, String value) {
    written.add('$key=$value');
    return super.setString(key, value);
  }

  @override
  Future<void> setDouble(String key, double value) {
    written.add('$key=$value');
    return super.setDouble(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) {
    written.add('$key=$value');
    return super.setBool(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('what Maps says is written nowhere the settings go', () async {
    final clock = FakeClock(start: DateTime(2026, 10, 24, 20, 58));
    final store = _Recording();
    final settings = AppSettings(store);
    await settings.load();
    final source = FakeNavSource(access: true);
    final service = NavService(
      settings: settings,
      source: source,
      clock: clock,
      scheduler: clock,
    )..start();
    addTearDown(service.dispose);

    settings.navEnabled.value = true;
    await Future<void>.delayed(Duration.zero);
    source.push(
      NavPosted(
        NavNotification(
          title: '650 m · Turn right onto Zzyzx Rd',
          text: 'toward Zzyzx Rd',
          subText: 'Arrive 9:25 PM',
          shortCriticalText: '650 m',
          progress: 100,
          progressMax: 9000,
          arrow: fixtureArrow('secretarrow'),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    clock.advance(const Duration(minutes: 5));
    source.push(const NavRemoved());
    await Future<void>.delayed(Duration.zero);

    final everything = store.written.join('\n');
    expect(everything, isNot(contains('Zzyzx')));
    expect(everything, isNot(contains('650')));
    expect(everything, isNot(contains('9:25')));
    expect(everything, isNot(contains('secretarrow')));
    // What was kept is the switch, and nothing else of the feature.
    expect(store.written.where((w) => w.contains('nav')).toList(), [
      'nav_enabled=true',
    ]);
  });

  test('no code that stores or sends anything imports the navigation feed', () {
    // Directories and files whose job is to keep or move data: trips and their
    // database, the exchange file, the session recordings, the connection log,
    // the key-value store.
    final storing = <String>[
      'lib/trips',
      'lib/exchange',
      'lib/insights',
      'lib/money',
      'lib/coach',
      'lib/core',
      'lib/platform/file_session_sink.dart',
      'lib/platform/exchange_files.dart',
      'lib/platform/exchange_host.dart',
      'lib/platform/shared_prefs_store.dart',
      'lib/platform/image_sharer.dart',
      'lib/obd/link_diary.dart',
      'lib/obd/transport/session_sink.dart',
      'lib/obd/survey',
      'lib/app/exchange_coordinator.dart',
      'lib/app/exchange_profile.dart',
      'lib/app/survey_drive.dart',
    ];
    final offenders = <String>[];
    final nav = RegExp(
      r'''^\s*(?:import|export)\s+['"][^'"]*(?:nav/|nav_service|nav_channel)[^'"]*['"]''',
      multiLine: true,
    );
    for (final path in storing) {
      final entity = FileSystemEntity.typeSync(path);
      expect(
        entity,
        isNot(FileSystemEntityType.notFound),
        reason: '$path is not there: the list is out of date',
      );
      final files = switch (entity) {
        FileSystemEntityType.directory =>
          Directory(path)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
        FileSystemEntityType.file => [File(path)],
        _ => <File>[],
      };
      for (final file in files) {
        if (nav.hasMatch(file.readAsStringSync())) offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('the feature itself opens no file and no socket', () {
    final offenders = <String>[];
    final io = RegExp(
      r'''^\s*import\s+['"]dart:(io|isolate)['"]''',
      multiLine: true,
    );
    for (final dir in ['lib/nav']) {
      for (final file in Directory(
        dir,
      ).listSync(recursive: true).whereType<File>()) {
        if (file.path.endsWith('.dart') &&
            io.hasMatch(file.readAsStringSync())) {
          offenders.add(file.path);
        }
      }
    }
    for (final file in [
      'lib/app/nav_service.dart',
      'lib/platform/nav_channel.dart',
    ]) {
      if (io.hasMatch(File(file).readAsStringSync())) offenders.add(file);
    }
    expect(offenders, isEmpty);
  });
}
