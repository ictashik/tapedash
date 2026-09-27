import 'package:flutter/widgets.dart';

import 'glyph_atlas.dart';

/// The caches the design system draws from: glyph atlases now, and the glow
/// sprites and grain that join them (DESIGN.md 9.3).
///
/// One is made for the app, and provided by a [TapeRenderScope]. Everything in it
/// is built once and reused, so nothing is rasterised while a frame is painted.
class TapeRenderKit {
  TapeRenderKit({int atlasCapacity = 24})
    : atlases = GlyphAtlasCache(capacity: atlasCapacity);

  /// Rendered numerals, by size, weight and density.
  final GlyphAtlasCache atlases;

  /// Frees every image. Call it when the app is done with the kit.
  void dispose() => atlases.clear();
}

/// Gives the widgets below it a [TapeRenderKit].
class TapeRenderScope extends InheritedWidget {
  const TapeRenderScope({super.key, required this.kit, required super.child});

  final TapeRenderKit kit;

  static TapeRenderKit of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TapeRenderScope>();
    assert(scope != null, 'No TapeRenderScope above this widget');
    return scope!.kit;
  }

  static TapeRenderKit? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TapeRenderScope>()?.kit;

  @override
  bool updateShouldNotify(TapeRenderScope oldWidget) => kit != oldWidget.kit;
}
