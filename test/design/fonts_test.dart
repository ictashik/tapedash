// The bundled fonts against DESIGN.md 4.5: what the subsets cover, that the rupee
// sign has a home, and that the licences travel with them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/design/tokens/typography.dart';

import '../support/ttf.dart';

/// The characters DESIGN.md 4.5 asks to be checked.
const _required = {
  '₹': 0x20B9,
  '°': 0xB0,
  '×': 0xD7,
  '≈': 0x2248,
  '−': 0x2212,
  '·': 0xB7,
};

/// Everything else the design types: the digits and symbols of the numerals, and
/// the punctuation of the copy in DESIGN.md 10.
const _copy =
    '0123456789.,%+:/ —–…“”’ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

TtfFile _font(String file) => TtfFile.read('${TapeFonts.directory}/$file');

void main() {
  group('the files', () {
    test('every declared font exists and is a TrueType file', () {
      for (final entry in TapeFonts.files.entries) {
        for (final file in entry.value) {
          final path = '${TapeFonts.directory}/$file';
          expect(File(path).existsSync(), isTrue, reason: path);
          final font = _font(file);
          expect(font.hasTable('cmap'), isTrue, reason: path);
          expect(font.hasTable('glyf'), isTrue, reason: path);
        }
      }
    });

    test('there is no font the app does not declare', () {
      final declared = {
        for (final f in TapeFonts.files.values.expand((f) => f)) f,
      };
      final onDisk = Directory(TapeFonts.directory)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.ttf') || n.endsWith('.otf'))
          .toSet();

      expect(onDisk, declared);
    });

    test('all of them are small enough to leave the APK budget alone', () {
      final total = Directory(TapeFonts.directory)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ttf'))
          .fold<int>(0, (sum, f) => sum + f.lengthSync());

      // CLAUDE.md 3: under 20 MB per ABI, fonts included, and they are subset.
      expect(total, lessThan(400 * 1024));
    });

    test('each family has its licence next to it', () {
      for (final name in ['OFL-Saira.txt', 'OFL-Barlow.txt']) {
        final text = File('${TapeFonts.directory}/$name').readAsStringSync();
        expect(
          text,
          contains('SIL OPEN FONT LICENSE Version 1.1'),
          reason: name,
        );
      }
      expect(File('${TapeFonts.directory}/SOURCE.md').existsSync(), isTrue);
    });

    test('each font carries its copyright and licence in its name table', () {
      for (final file in TapeFonts.files.values.expand((f) => f)) {
        final font = _font(file);
        expect(font.name(0), contains('Copyright'), reason: file);
        expect(font.name(13), contains('Open Font License'), reason: file);
      }
    });
  });

  group('Saira', () {
    final saira = _font('Saira-Variable.ttf');

    test('has every character DESIGN.md 4.5 asks about', () {
      for (final entry in _required.entries) {
        expect(saira.codePoints, contains(entry.value), reason: entry.key);
      }
    });

    test('has the digits, the symbols of the numerals and the wordmark', () {
      for (final c in '0123456789.,%+:/ TAPEDASH'.runes) {
        expect(saira.codePoints, contains(c), reason: String.fromCharCode(c));
      }
    });

    test('has the arrows of the HUD alignment pattern', () {
      for (final c in [0x2190, 0x2191, 0x2192, 0x2193]) {
        expect(saira.codePoints, contains(c), reason: c.toRadixString(16));
      }
    });

    test('is variable in weight and width, over the range the design uses', () {
      expect(saira.axes['wght'], (300.0, 300.0, 800.0));
      expect(saira.axes['wdth'], (100.0, 100.0, 125.0));
      // The numerals are set wide, and MONO is Light and the HUD SemiBold or more.
      expect(TapeType.numeralWidth, inInclusiveRange(112, 125));
    });
  });

  group('Barlow', () {
    const barlow = [
      'Barlow-Regular.ttf',
      'Barlow-Medium.ttf',
      'Barlow-SemiBold.ttf',
      'BarlowSemiCondensed-Regular.ttf',
      'BarlowSemiCondensed-Medium.ttf',
      'BarlowSemiCondensed-SemiBold.ttf',
    ];

    test(
      'has the copy, and every symbol DESIGN.md 4.5 asks about but the rupee',
      () {
        for (final file in barlow) {
          final font = _font(file);
          for (final entry in _required.entries) {
            if (entry.key == '₹') continue;
            expect(
              font.codePoints,
              contains(entry.value),
              reason: '$file ${entry.key}',
            );
          }
          for (final c in _copy.runes) {
            expect(
              font.codePoints,
              contains(c),
              reason: '$file ${String.fromCharCode(c)}',
            );
          }
        }
      },
    );

    test('has no rupee sign, so text in it falls back to Saira for it', () {
      for (final file in barlow) {
        expect(_font(file).codePoints, isNot(contains(0x20B9)), reason: file);
      }

      // The label and parked styles list Saira, and only Saira, as the fallback.
      expect(TapeType.label(size: 12).fontFamilyFallback, [
        TapeFontFamily.saira,
      ]);
      expect(TapeType.body().fontFamilyFallback, [TapeFontFamily.saira]);
      expect(TapeType.button().fontFamilyFallback, [TapeFontFamily.saira]);
    });
  });
}
