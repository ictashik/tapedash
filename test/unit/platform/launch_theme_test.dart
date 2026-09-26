// Guards the "no white flash, ever" rule (CLAUDE.md 3, DESIGN.md 12) and the
// landscape-only rule by reading the Android resources directly.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';

const _res = 'android/app/src/main/res';
const _voidColor = '@color/tapedash_void';

/// The `<item>` entries of the `<style name="[name]">` block, by attribute name.
Map<String, String> _styleItems(String xml, String name) {
  final block = RegExp(
    '<style name="$name"[^>]*>(.*?)</style>',
    dotAll: true,
  ).firstMatch(xml);
  if (block == null) return const {};
  return {
    for (final m in RegExp(
      r'<item name="([^"]+)">([^<]*)</item>',
    ).allMatches(block.group(1)!))
      m.group(1)!: m.group(2)!.trim(),
  };
}

List<File> _files(String fileName, String dirPrefix) => Directory(_res)
    .listSync()
    .whereType<Directory>()
    .where(
      (d) => d.uri.pathSegments.reversed.elementAt(1).startsWith(dirPrefix),
    )
    .map((d) => File('${d.path}/$fileName'))
    .where((f) => f.existsSync())
    .toList();

void main() {
  test('tapedash_void is the same colour as the Dart void token', () {
    final xml = File('$_res/values/colors.xml').readAsStringSync();
    final match = RegExp(
      r'<color name="tapedash_void">#([0-9A-Fa-f]{8})</color>',
    ).firstMatch(xml);

    expect(match, isNotNull, reason: 'tapedash_void must be defined');
    expect(
      int.parse(match!.group(1)!, radix: 16),
      TapeColors.voidColor.toARGB32(),
    );
  });

  group('every theme variant paints the launch window as void', () {
    final styleFiles = _files('styles.xml', 'values');

    test('there is a base styles.xml', () {
      expect(
        styleFiles.map((f) => f.path),
        contains('$_res/values/styles.xml'),
      );
    });

    for (final file in styleFiles) {
      for (final theme in ['LaunchTheme', 'NormalTheme']) {
        test('${file.path} $theme', () {
          final items = _styleItems(file.readAsStringSync(), theme);
          if (items.isEmpty) return; // not overridden in this variant

          expect(
            items['android:windowBackground'],
            anyOf(_voidColor, '@drawable/launch_background'),
          );
          expect(items['android:colorBackground'], _voidColor);
          if (theme == 'LaunchTheme' && file.path.contains('values-v31')) {
            expect(items['android:windowSplashScreenBackground'], _voidColor);
          }
        });
      }
    }

    test('Android 12+ splash background is set explicitly', () {
      final xml = File('$_res/values-v31/styles.xml').readAsStringSync();
      expect(
        _styleItems(xml, 'LaunchTheme')['android:windowSplashScreenBackground'],
        _voidColor,
      );
    });
  });

  test('the launch drawable is void and every variant agrees', () {
    final drawables = _files('launch_background.xml', 'drawable');
    expect(drawables, isNotEmpty);

    for (final file in drawables) {
      final xml = file.readAsStringSync().replaceAll(
        RegExp('<!--.*?-->', dotAll: true),
        '',
      );
      final layers = RegExp(
        r'android:drawable="([^"]+)"',
      ).allMatches(xml).map((m) => m.group(1)).toList();

      expect(layers, isNotEmpty, reason: file.path);
      expect(layers.first, _voidColor, reason: file.path);
      expect(xml, isNot(contains('white')), reason: file.path);
      expect(xml, isNot(contains('colorBackground')), reason: file.path);
    }
  });

  test('the main activity is landscape only, in both directions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:screenOrientation="sensorLandscape"'));
  });
}
