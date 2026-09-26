// The layering and time rules from CLAUDE.md 5 and 6, checked against lib/.
//
// Most of these directories have no code yet. The test is here first so that
// the rules hold from the first line written.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Directories that must run under plain `dart`, since tool/sim_server.dart and
/// tool/record_sim.dart import them. CLAUDE.md 6 lists sim, obd, vehicle, fuel,
/// money, coach and trips; core and location are added because the simulator
/// depends on them and so they have to be Flutter-free too.
const _pureDirs = [
  'core',
  'sim',
  'obd',
  'location',
  'vehicle',
  'fuel',
  'money',
  'coach',
  'trips',
];

/// The only files that may touch real time: the real implementations of the
/// interfaces everything else is given.
const _realTimeAllowed = {'lib/core/clock.dart', 'lib/core/scheduler.dart'};

final _flutterImport = RegExp(
  r'''^\s*(?:import|export)\s+['"](package:flutter[^'"]*|dart:ui)['"]''',
);

final _realTime = RegExp(
  r'DateTime\.now\s*\(|\bStopwatch\s*\(|\bTimer\s*(?:\.periodic)?\s*\(|'
  r'\bFuture(?:<[^>]*>)?\.delayed\s*\(',
);

/// Every rule broken under `<root>/lib`, as `path:line: message`.
List<String> findViolations(Directory root) {
  final violations = <String>[];
  for (final dir in _pureDirs) {
    final directory = Directory('${root.path}/lib/$dir');
    if (!directory.existsSync()) continue;

    final files =
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final path = file.path.substring(root.path.length + 1);
      // CLAUDE.md 6: trips is pure Dart "except the sqflite adapter".
      final isSqfliteAdapter =
          path.startsWith('lib/trips/') && path.contains('sqflite');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].replaceFirst(RegExp(r'//.*$'), '');
        if (!isSqfliteAdapter && _flutterImport.hasMatch(code)) {
          violations.add(
            '$path:${i + 1}: lib/$dir must not import Flutter or dart:ui',
          );
        }
        if (!_realTimeAllowed.contains(path) && _realTime.hasMatch(code)) {
          violations.add(
            '$path:${i + 1}: use the injected Clock or Scheduler, not real time',
          );
        }
      }
    }
  }
  return violations;
}

void main() {
  test('lib/ follows the layering and time rules', () {
    expect(findViolations(Directory.current), isEmpty);
  });

  group('the check itself', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('tapedash_architecture_');
      addTearDown(() => root.deleteSync(recursive: true));
    });

    void write(String path, String content) {
      final file = File('${root.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('passes clean code', () {
      write('lib/sim/model.dart', "import 'dart:math';\nvoid step() {}\n");

      expect(findViolations(root), isEmpty);
    });

    for (final import in [
      "import 'package:flutter/widgets.dart';",
      'import "package:flutter/foundation.dart";',
      "import 'package:flutter_test/flutter_test.dart';",
      "import 'dart:ui';",
      "export 'dart:ui' show Color;",
    ]) {
      test('rejects $import in a pure directory', () {
        write('lib/obd/thing.dart', '$import\n');

        expect(findViolations(root), [
          'lib/obd/thing.dart:1: lib/obd must not import Flutter or dart:ui',
        ]);
      });
    }

    test('allows Flutter outside the pure directories', () {
      write('lib/ui/page.dart', "import 'package:flutter/widgets.dart';\n");
      write('lib/platform/x.dart', "import 'package:flutter/services.dart';\n");

      expect(findViolations(root), isEmpty);
    });

    test('allows Flutter in the sqflite adapter of trips only', () {
      write(
        'lib/trips/sqflite_trip_repository.dart',
        "import 'package:flutter/foundation.dart';\n",
      );
      write(
        'lib/trips/trip.dart',
        "import 'package:flutter/foundation.dart';\n",
      );

      expect(findViolations(root), [
        'lib/trips/trip.dart:1: lib/trips must not import Flutter or dart:ui',
      ]);
    });

    for (final call in [
      'DateTime.now()',
      'DateTime.now ()',
      'Stopwatch()',
      'Stopwatch()..start()',
      'Timer(d, f)',
      'Timer.periodic(d, f)',
      'Future.delayed(d)',
      'Future<void>.delayed(d)',
    ]) {
      test('rejects $call in a pure directory', () {
        write('lib/vehicle/state.dart', 'final x = $call;\n');

        expect(findViolations(root), [
          'lib/vehicle/state.dart:1: '
              'use the injected Clock or Scheduler, not real time',
        ]);
      });
    }

    test('allows real time in the Clock and Scheduler implementations', () {
      write('lib/core/clock.dart', 'final x = DateTime.now();\n');
      write('lib/core/scheduler.dart', 'final t = Timer(d, f);\n');

      expect(findViolations(root), isEmpty);
    });

    test('rejects real time elsewhere in core', () {
      write('lib/core/fake_clock.dart', 'final x = DateTime.now();\n');

      expect(findViolations(root), hasLength(1));
    });

    test('allows real time outside the pure directories', () {
      write('lib/ui/ticker.dart', 'final t = Timer(d, f);\n');
      write('lib/app/x.dart', 'final x = DateTime.now();\n');

      expect(findViolations(root), isEmpty);
    });

    test('ignores comments and matches whole words', () {
      write('lib/fuel/x.dart', '''
// DateTime.now() is banned, and so is Timer(d, f).
/// Do not import 'package:flutter/widgets.dart' here.
final a = MyTimer(d);
final b = clock.now();
final c = Stopwatches(1);
''');

      expect(findViolations(root), isEmpty);
    });

    test('reports every violation with its line', () {
      write('lib/money/x.dart', '''
void a() {}
final t = DateTime.now();
void b() {}
final u = Timer(d, f);
''');

      expect(findViolations(root), [
        'lib/money/x.dart:2: use the injected Clock or Scheduler, not real time',
        'lib/money/x.dart:4: use the injected Clock or Scheduler, not real time',
      ]);
    });
  });
}
