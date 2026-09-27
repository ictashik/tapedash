import 'package:flutter/services.dart';

import '../tokens/typography.dart';

/// Registers the bundled fonts with the engine (DESIGN.md 4.5).
///
/// The fonts are declared as assets, not under `flutter: fonts:`, and loaded here.
/// That way the app can await them before its first frame, so the cold open never
/// shows in a fallback face, and the tests load them by the same code and so draw
/// goldens in the real typography (DESIGN.md 14.1).
abstract final class TapeFonts {
  /// The files of each family, under the asset folder. Weights come from each
  /// file's own tables: Saira is one variable file, and Barlow has a file per
  /// weight.
  static const Map<String, List<String>> files = {
    TapeFontFamily.saira: ['Saira-Variable.ttf'],
    TapeFontFamily.barlowSemiCondensed: [
      'BarlowSemiCondensed-Regular.ttf',
      'BarlowSemiCondensed-Medium.ttf',
      'BarlowSemiCondensed-SemiBold.ttf',
    ],
    TapeFontFamily.barlow: [
      'Barlow-Regular.ttf',
      'Barlow-Medium.ttf',
      'Barlow-SemiBold.ttf',
    ],
  };

  static const String directory = 'assets/fonts';

  static Future<void>? _loading;

  /// Loads every family from [bundle] (the root bundle by default). Calling it
  /// again returns the same work, and after a failure it tries afresh.
  static Future<void> load([AssetBundle? bundle]) {
    final loading = _loading ??= _load(bundle ?? rootBundle);
    return loading.catchError((Object error) {
      _loading = null;
      throw error;
    });
  }

  static Future<void> _load(AssetBundle bundle) async {
    for (final entry in files.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(bundle.load('$directory/$file'));
      }
      await loader.load();
    }
  }
}
