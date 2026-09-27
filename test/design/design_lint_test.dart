// The design lint (DESIGN.md 14.2): no Material look and no design constants
// outside the tokens.
//
// DESIGN.md 13.1 bans a list of Material widgets in lib/ui/, and bans colour,
// text style, duration and spring literals outside lib/ui/design/tokens/. The
// look of the app has to come from one place, or it cannot be tuned in one place.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the rules hold. The app shell composes the UI, so it is held to them too.
const _linted = ['lib/ui', 'lib/app'];

/// The one place design constants may be written.
const _tokens = 'lib/ui/design/tokens/';

/// The Material widgets DESIGN.md 13.1 bans, matched as whole words.
const _bannedWidgets = [
  'AppBar',
  'Card',
  'ElevatedButton',
  'TextButton',
  'OutlinedButton',
  'FloatingActionButton',
  'Switch',
  'Slider',
  'Checkbox',
  'Radio',
  'ListTile',
  'SnackBar',
  'Dialog',
  'AlertDialog',
  'CircularProgressIndicator',
  'LinearProgressIndicator',
  'InkWell',
  'InkResponse',
  'BottomNavigationBar',
  'TabBar',
  'Drawer',
  'Scaffold',
  'Material',
  'MaterialApp',
  'Icons',
];

class _Rule {
  const _Rule(this.pattern, this.message, {this.tokensOnly = false});

  final RegExp pattern;
  final String message;

  /// True if the rule is about a design constant, which the tokens may write.
  final bool tokensOnly;
}

final List<_Rule> _rules = [
  for (final widget in _bannedWidgets)
    _Rule(
      RegExp('\\b$widget\\b'),
      '$widget is a Material widget, which the design bans (DESIGN.md 13.1)',
    ),
  _Rule(
    RegExp(r'''package:flutter/material\.dart'''),
    'lib/ui must not import Material (DESIGN.md 13.1)',
  ),
  _Rule(
    RegExp(r'\bColor\(\s*0x|\bColor\.from(?:ARGB|RGBO)\(\s*\d|\bColors\.'),
    'a colour literal: colours come from the tokens (DESIGN.md 13.1)',
    tokensOnly: true,
  ),
  _Rule(
    RegExp(r'\bTextStyle\('),
    'a TextStyle made outside the typography tokens (DESIGN.md 13.1)',
    tokensOnly: true,
  ),
  _Rule(
    RegExp(
      r'\bDuration\(\s*(?:days|hours|minutes|seconds|milliseconds|microseconds)\s*:\s*\d',
    ),
    'a duration literal: durations come from the tokens (DESIGN.md 13.1)',
    tokensOnly: true,
  ),
  _Rule(
    RegExp(r'\bSpringDescription\b|\bSpringSpec\(|\bCubic\(|\bCurves\.'),
    'a spring or curve constant: motion comes from the tokens (DESIGN.md 13.1)',
    tokensOnly: true,
  ),
];

/// Every rule broken under `<root>/lib`, as `path:line: message`.
List<String> findDesignViolations(Directory root) {
  final violations = <String>[];
  for (final dir in _linted) {
    final directory = Directory('${root.path}/$dir');
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
      final inTokens = path.startsWith(_tokens);
      var inBlock = false;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        // Block comments, then line comments, then the insides of strings.
        if (inBlock) {
          final end = line.indexOf('*/');
          if (end < 0) continue;
          line = line.substring(end + 2);
          inBlock = false;
        }
        while (true) {
          final start = line.indexOf('/*');
          if (start < 0) break;
          final end = line.indexOf('*/', start + 2);
          if (end < 0) {
            line = line.substring(0, start);
            inBlock = true;
            break;
          }
          line = line.substring(0, start) + line.substring(end + 2);
        }
        line = line.replaceFirst(RegExp(r'//.*$'), '');
        // A Material import is checked on the raw line, since it is a string.
        final imports = RegExp(
          r'''^\s*(?:import|export)\s+['"]''',
        ).hasMatch(line);
        if (!imports) {
          line = line.replaceAll(
            RegExp(
              r"'(?:\\.|[^'\\])*'|"
              r'"(?:\\.|[^"\\])*"',
            ),
            "''",
          );
        }

        for (final rule in _rules) {
          if (rule.tokensOnly && inTokens) continue;
          if (rule.pattern.hasMatch(line)) {
            violations.add('$path:${i + 1}: ${rule.message}');
          }
        }
      }
    }
  }
  return violations;
}

void main() {
  test('lib/ui and lib/app follow the design rules', () {
    expect(findDesignViolations(Directory.current), isEmpty);
  });

  group('the check itself', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('tapedash_design_lint_');
      addTearDown(() => root.deleteSync(recursive: true));
    });

    void write(String path, String content) {
      final file = File('${root.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('passes clean code', () {
      write('lib/ui/pages/drive.dart', '''
import 'package:flutter/widgets.dart';
class Drive extends StatelessWidget {
  Widget build(BuildContext context) => const SizedBox();
}
''');

      expect(findDesignViolations(root), isEmpty);
    });

    for (final widget in [
      'AppBar(title: t)',
      'Card(child: c)',
      'ElevatedButton(onPressed: f, child: c)',
      'TextButton(onPressed: f, child: c)',
      'OutlinedButton(onPressed: f, child: c)',
      'FloatingActionButton(onPressed: f)',
      'Switch(value: v, onChanged: f)',
      'Slider(value: v, onChanged: f)',
      'Checkbox(value: v, onChanged: f)',
      'Radio<int>(value: 1)',
      'ListTile(title: t)',
      'SnackBar(content: c)',
      'AlertDialog(title: t)',
      'CircularProgressIndicator()',
      'LinearProgressIndicator()',
      'InkWell(onTap: f)',
      'BottomNavigationBar(items: i)',
      'TabBar(tabs: t)',
      'Drawer(child: c)',
      'Scaffold(body: b)',
      'Icon(Icons.add)',
    ]) {
      test('rejects $widget', () {
        write('lib/ui/pages/x.dart', 'final w = $widget;\n');

        expect(findDesignViolations(root), hasLength(1));
      });
    }

    test('rejects the Material import', () {
      write('lib/ui/pages/x.dart', "import 'package:flutter/material.dart';\n");

      expect(findDesignViolations(root), [
        'lib/ui/pages/x.dart:1: lib/ui must not import Material (DESIGN.md 13.1)',
      ]);
    });

    test('matches whole words, so our own names are fine', () {
      write('lib/ui/pages/x.dart', '''
class LabSlider {}
class TapeSwitch {}
class MaterialColorful {}
final a = LabSlider();
final b = const CardinalDirection();
final c = TapeIcon.rupee;
''');

      expect(findDesignViolations(root), isEmpty);
    });

    test('ignores comments and strings', () {
      write('lib/ui/pages/x.dart', '''
// A Card, a Scaffold and Color(0xFF000000) are not allowed here.
/// Never use a Slider or a TextStyle(fontSize: 1).
/* Duration(milliseconds: 300)
   also Switch */
final label = 'Drawer and Color(0xFF000000)';
final other = "Dialog";
''');

      expect(findDesignViolations(root), isEmpty);
    });

    for (final (literal, what) in [
      ('Color(0xFF123456)', 'a hex colour'),
      ('Color.fromARGB(255, 1, 2, 3)', 'an ARGB colour'),
      ('Color.fromRGBO(1, 2, 3, 0.5)', 'an RGBO colour'),
      ('Colors.red', 'a named colour'),
      ("TextStyle(fontFamily: 'x')", 'a text style'),
      ('Duration(milliseconds: 300)', 'a millisecond duration'),
      ('Duration(seconds: 1)', 'a second duration'),
      ('SpringDescription(mass: 1, stiffness: 2, damping: 3)', 'a spring'),
      (
        'SpringDescription.withDampingRatio(mass: 1, stiffness: 2)',
        'a spring ratio',
      ),
      ('SpringSpec(1, 2)', 'a spring token'),
      ('Cubic(0, 0, 1, 1)', 'a curve'),
      ('Curves.easeOut', 'a stock curve'),
    ]) {
      test('rejects $what outside the tokens', () {
        write('lib/ui/components/x.dart', 'final v = $literal;\n');

        expect(findDesignViolations(root), hasLength(1));
      });

      test('allows $what in the tokens', () {
        write('lib/ui/design/tokens/x.dart', 'final v = $literal;\n');

        expect(findDesignViolations(root), isEmpty);
      });
    }

    test('allows computed colours and durations', () {
      write('lib/ui/components/x.dart', '''
final a = Color.fromARGB(alpha, 255, 255, 255);
final b = Duration(microseconds: micros);
final c = base.withValues(alpha: 0.5);
final d = Duration.zero;
''');

      expect(findDesignViolations(root), isEmpty);
    });

    test('holds lib/app to the same rules, and leaves the rest alone', () {
      write('lib/app/shell.dart', 'final w = Scaffold(body: b);\n');
      write('lib/sim/x.dart', 'final w = Scaffold(body: b);\n');

      expect(findDesignViolations(root), [
        'lib/app/shell.dart:1: Scaffold is a Material widget, which the design bans (DESIGN.md 13.1)',
      ]);
    });

    test('reports each violation with its file and line', () {
      write('lib/ui/pages/a.dart', '''
void a() {}
final c = Card();
void b() {}
final d = Drawer();
''');

      expect(findDesignViolations(root), [
        'lib/ui/pages/a.dart:2: Card is a Material widget, which the design bans (DESIGN.md 13.1)',
        'lib/ui/pages/a.dart:4: Drawer is a Material widget, which the design bans (DESIGN.md 13.1)',
      ]);
    });
  });
}
