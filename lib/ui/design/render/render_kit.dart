import 'package:flutter/widgets.dart';

import 'glow_cache.dart';
import 'glyph_atlas.dart';
import 'grain.dart';
import 'mesh.dart';
import 'seven_segment.dart';

/// The caches the design system draws from: glyph atlases, glow sprites, the grain
/// tile (DESIGN.md 9.3).
///
/// One is made for the app, and provided by a [TapeRenderScope]. Everything in it
/// is built once and reused, so nothing is rasterised while a frame is painted.
class TapeRenderKit {
  TapeRenderKit({int atlasCapacity = 24, int grainSeed = 7})
    : atlases = GlyphAtlasCache(capacity: atlasCapacity),
      glows = GlowCache(),
      grain = GrainTile.generate(seed: grainSeed);

  /// Rendered numerals, by size, weight and density.
  final GlyphAtlasCache atlases;

  /// Blurred halo sprites.
  final GlowCache glows;

  /// The noise laid over the void.
  final GrainTile grain;

  final Map<(double, double, double, double), SevenSegmentAtlas> _segments = {};

  /// The seven-segment atlas for digits [heightLp] tall (DESIGN.md 6.17), made
  /// when first asked for. A [glowSigmaLp] above 0 gives the halo variant.
  SevenSegmentAtlas segments({
    required double heightLp,
    required double devicePixelRatio,
    double glowSigmaLp = 0,
    double resolution = 1,
  }) {
    final key = (heightLp, devicePixelRatio, glowSigmaLp, resolution);
    final existing = _segments.remove(key);
    if (existing != null && !existing.isDisposed) {
      _segments[key] = existing;
      return existing;
    }
    final atlas = SevenSegmentAtlas.build(
      heightLp: heightLp,
      devicePixelRatio: devicePixelRatio,
      glowSigmaLp: glowSigmaLp,
      resolution: resolution,
    );
    _segments[key] = atlas;
    while (_segments.length > 8) {
      _segments.remove(_segments.keys.first)!.dispose();
    }
    return atlas;
  }

  MeshTile? _mesh;
  double _meshDensity = 0;

  /// The VFD mesh for a screen of [devicePixelRatio], made when first asked for.
  MeshTile mesh(double devicePixelRatio) {
    if (_mesh == null || _meshDensity != devicePixelRatio) {
      _mesh?.dispose();
      _mesh = MeshTile.generate(devicePixelRatio: devicePixelRatio);
      _meshDensity = devicePixelRatio;
    }
    return _mesh!;
  }

  /// Frees every image. Call it when the app is done with the kit.
  void dispose() {
    atlases.clear();
    glows.clear();
    for (final atlas in _segments.values) {
      atlas.dispose();
    }
    _segments.clear();
    grain.dispose();
    _mesh?.dispose();
    _mesh = null;
  }
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
