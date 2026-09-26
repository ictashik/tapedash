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

final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

/// Parts of the app that the pure directories must never reach into: they hold
/// widgets and platform channels.
const _appLayers = {'ui', 'app', 'platform'};

/// Directories at the bottom of the stack, and all they may import. `core` is
/// the base of everything, and `sim` is the simulator, which sits on it alone
/// so that nothing it depends on can depend on it.
const _bottomLayers = {
  'core': {'core'},
  'sim': {'core', 'sim'},
};

/// The directory of `lib/` that an import of [target], made from the file at
/// [fromPath] (relative to `lib/`), points into. Null for `dart:` and
/// other packages, and for anything outside `lib/`.
String? _libDirectory(String fromPath, String target) {
  final String path;
  if (target.startsWith('package:tapedash/')) {
    path = target.substring('package:tapedash/'.length);
  } else if (target.contains(':')) {
    return null;
  } else {
    path = Uri.parse(fromPath).resolve(target).path;
  }
  if (path.startsWith('..')) return null;
  final slash = path.indexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

/// Every rule broken under `<root>/lib`, as `path:line: message`.
List<String> findViolations(Directory root) {
  final violations = <String>[];
  final lib = Directory('${root.path}/lib');
  if (!lib.existsSync()) return violations;

  final files =
      lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final path = file.path.substring(root.path.length + 1);
    final fromLib = path.substring('lib/'.length);
    final slash = fromLib.indexOf('/');
    final dir = slash < 0 ? '' : fromLib.substring(0, slash);
    final isPure = _pureDirs.contains(dir);
    // CLAUDE.md 6: trips is pure Dart "except the sqflite adapter".
    final isSqfliteAdapter = dir == 'trips' && path.contains('sqflite');
    final lines = file.readAsLinesSync();

    for (var i = 0; i < lines.length; i++) {
      final code = lines[i].replaceFirst(RegExp(r'//.*$'), '');
      final where = '$path:${i + 1}';

      if (isPure &&
          !_realTimeAllowed.contains(path) &&
          _realTime.hasMatch(code)) {
        violations.add(
          '$where: use the injected Clock or Scheduler, not real time',
        );
      }
      if (isPure && !isSqfliteAdapter && _flutterImport.hasMatch(code)) {
        violations.add('$where: lib/$dir must not import Flutter or dart:ui');
      }

      final target = _directive.firstMatch(code)?.group(1);
      if (target == null) continue;
      final into = _libDirectory(fromLib, target);
      if (into != null && isPure && _appLayers.contains(into)) {
        violations.add('$where: lib/$dir must not import lib/$into');
      }
      final allowed = _bottomLayers[dir];
      if (into != null && allowed != null && !allowed.contains(into)) {
        violations.add(
          '$where: lib/$dir may only import ${allowed.map((d) => 'lib/$d').join(' and ')}, '
          'not lib/$into',
        );
      }
      if (dir == 'ui' &&
          (target.contains('sqflite') ||
              (into == 'obd' && target.contains('transport')))) {
        violations.add(
          '$where: lib/ui must not touch transports or the database: $target',
        );
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

    group('imports', () {
      test('a pure directory may not import the app layers', () {
        write('lib/fuel/a.dart', "import '../ui/page.dart';\n");
        write('lib/fuel/b.dart', "import 'package:tapedash/app/app.dart';\n");
        write(
          'lib/obd/transport/c.dart',
          "import '../../platform/device_channel.dart';\n",
        );
        write('lib/coach/d.dart', "export '../ui/page.dart';\n");

        expect(findViolations(root), [
          'lib/coach/d.dart:1: lib/coach must not import lib/ui',
          'lib/fuel/a.dart:1: lib/fuel must not import lib/ui',
          'lib/fuel/b.dart:1: lib/fuel must not import lib/app',
          'lib/obd/transport/c.dart:1: lib/obd must not import lib/platform',
        ]);
      });

      test('the app layers may import the pure ones, and each other', () {
        write('lib/ui/page.dart', "import '../vehicle/state.dart';\n");
        write('lib/app/x.dart', "import '../platform/y.dart';\n");
        write(
          'lib/platform/y.dart',
          "import 'package:tapedash/core/clock.dart';\n",
        );

        expect(findViolations(root), isEmpty);
      });

      test('pure directories may import each other and their own files', () {
        write(
          'lib/obd/transport/t.dart',
          "import '../../sim/x.dart';\nimport 'transport.dart';\n"
              "import '../pids/pid.dart';\nimport 'dart:async';\n"
              "import 'package:collection/collection.dart';\n",
        );

        expect(findViolations(root), isEmpty);
      });

      test('sim sits on core alone', () {
        write('lib/sim/a.dart', "import '../obd/transport/transport.dart';\n");
        write('lib/sim/b.dart', "import 'package:tapedash/location/x.dart';\n");
        write(
          'lib/sim/c.dart',
          "import '../core/clock.dart';\n"
              "import 'package:tapedash/core/scheduler.dart';\n"
              "import 'engine_spec.dart';\nimport 'dart:math';\n",
        );

        expect(findViolations(root), [
          'lib/sim/a.dart:1: lib/sim may only import lib/core and lib/sim, '
              'not lib/obd',
          'lib/sim/b.dart:1: lib/sim may only import lib/core and lib/sim, '
              'not lib/location',
        ]);
      });

      test('core sits on nothing', () {
        write('lib/core/a.dart', "import '../sim/x.dart';\n");
        write('lib/core/b.dart', "import 'clock.dart';\n");

        expect(findViolations(root), [
          'lib/core/a.dart:1: lib/core may only import lib/core, not lib/sim',
        ]);
      });

      test('ui may not touch transports or the database', () {
        write('lib/ui/a.dart', "import '../obd/transport/transport.dart';\n");
        write(
          'lib/ui/b.dart',
          "import 'package:tapedash/obd/transport/sim_transport.dart';\n",
        );
        write('lib/ui/c.dart', "import 'package:sqflite/sqflite.dart';\n");
        write('lib/ui/d.dart', "import '../obd/pids/pid.dart';\n");

        expect(findViolations(root), [
          'lib/ui/a.dart:1: lib/ui must not touch transports or the '
              'database: ../obd/transport/transport.dart',
          'lib/ui/b.dart:1: lib/ui must not touch transports or the '
              'database: package:tapedash/obd/transport/sim_transport.dart',
          'lib/ui/c.dart:1: lib/ui must not touch transports or the '
              'database: package:sqflite/sqflite.dart',
        ]);
      });

      test('an import that leaves lib is not judged', () {
        write('lib/sim/a.dart', "import '../../tool/x.dart';\n");

        expect(findViolations(root), isEmpty);
      });

      test(
        'a commented-out import is ignored, and a violation has its line',
        () {
          write('lib/fuel/a.dart', """
// import '../ui/page.dart';
void a() {}
import '../ui/page.dart';
""");

          expect(findViolations(root), [
            'lib/fuel/a.dart:3: lib/fuel must not import lib/ui',
          ]);
        },
      );
    });
  });
}
