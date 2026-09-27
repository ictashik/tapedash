import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// What a glyph atlas is made of: which characters, at what size, weight and
/// width, for a screen of what density (DESIGN.md 9.3).
///
/// There is no colour in it. Glyphs are drawn white, and the colour role and the
/// alpha of each sprite are set when it is drawn, so one atlas serves every
/// colour a numeral is ever drawn in.
class GlyphAtlasSpec {
  const GlyphAtlasSpec({
    required this.sizeLp,
    required this.devicePixelRatio,
    required this.weight,
    this.width = TapeType.numeralWidth,
    this.glowSigmaLp = 0,
    this.resolution = 1,
    this.characters = GlyphSet.numerals,
  });

  /// The font size, in logical pixels.
  final double sizeLp;

  final double devicePixelRatio;

  /// The `wght` of Saira.
  final double weight;

  /// The `wdth` of Saira.
  final double width;

  /// The blur of a halo, in logical pixels, or 0 for crisp glyphs. A halo atlas
  /// holds the same glyphs, blurred (DESIGN.md 4.9).
  final double glowSigmaLp;

  /// The share of full resolution the atlas is drawn at: 0.5 for the half-resolution
  /// halos of Tier 1 (DESIGN.md 9.1).
  final double resolution;

  final String characters;

  bool get isGlow => glowSigmaLp > 0;

  @override
  bool operator ==(Object other) =>
      other is GlyphAtlasSpec &&
      other.sizeLp == sizeLp &&
      other.devicePixelRatio == devicePixelRatio &&
      other.weight == weight &&
      other.width == width &&
      other.glowSigmaLp == glowSigmaLp &&
      other.resolution == resolution &&
      other.characters == characters;

  @override
  int get hashCode => Object.hash(
    sizeLp,
    devicePixelRatio,
    weight,
    width,
    glowSigmaLp,
    resolution,
    characters,
  );

  @override
  String toString() =>
      'GlyphAtlasSpec($sizeLp lp, x$devicePixelRatio, w$weight, wdth $width'
      '${isGlow ? ', glow $glowSigmaLp' : ''}${resolution == 1 ? '' : ', x$resolution'})';
}

/// The characters live numerals are drawn from (DESIGN.md 9.3): the digits and
/// `. , − + × ₹ % ° : /`.
abstract final class GlyphSet {
  /// The minus sign is U+2212, not a hyphen (DESIGN.md 4.5).
  static const String numerals = '0123456789.,−+×₹%°:/';

  /// The letters of the wordmark (DESIGN.md 12), drawn from an atlas too, so it can
  /// carry a halo.
  static const String wordmark = 'TAPEDASH';
}

/// One glyph in an atlas.
class Glyph {
  const Glyph({
    required this.code,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.advance,
  });

  /// The code point.
  final int code;

  /// Where its sprite is in the atlas image, in atlas pixels.
  final double left, top, right, bottom;

  /// How far the pen moves after it, in logical pixels.
  final double advance;
}

/// Glyphs rendered once into an image, to be drawn with `Canvas.drawRawAtlas`
/// (DESIGN.md 9.3). No `TextPainter` layout is done while painting a frame.
///
/// Each sprite is a cell holding one glyph, with padding around it (for the blur
/// of a halo), and with its baseline at a fixed height in the cell, so that
/// sprites line up by drawing them at one baseline.
class GlyphAtlas {
  GlyphAtlas._({
    required this.spec,
    required this.image,
    required this.scale,
    required this.glyphs,
    required this.digitAdvance,
    required this.padding,
    required this.baseline,
    required this.cellHeight,
  });

  final GlyphAtlasSpec spec;

  /// The atlas image: white glyphs on transparent.
  final ui.Image image;

  /// Logical pixels per atlas pixel. Draw each sprite at this scale.
  final double scale;

  final Map<int, Glyph> glyphs;

  /// The advance of every digit, which is the same for all ten: they are
  /// tabular, and a digit's place never depends on which digit it is.
  final double digitAdvance;

  /// Transparent border round each glyph in its sprite, in logical pixels.
  final double padding;

  /// The distance from the top of a sprite to the baseline, in logical pixels.
  final double baseline;

  /// The height of a sprite, in logical pixels.
  final double cellHeight;

  /// The share of a font size above the baseline that a cell holds: more than the
  /// tallest glyph (the slash, at 0.743 em).
  static const double _aboveEm = 0.80;

  /// And below it: the comma descends to 0.127 em.
  static const double _belowEm = 0.18;

  static const int _maxWidth = 2048;

  /// Renders the atlas for [spec]. It draws with the fonts registered by
  /// `TapeFonts`, so load them first.
  static GlyphAtlas build(GlyphAtlasSpec spec) {
    final scale = 1 / (spec.devicePixelRatio * spec.resolution);
    final sizePx = spec.sizeLp / scale;
    final sigmaPx = spec.glowSigmaLp / scale;
    final pad = spec.isGlow ? (3 * sigmaPx).ceil() + 1 : 1;

    // One painter per character, laid out white (or, for a halo, blurred).
    final painters = <int, TextPainter>{};
    var digitAdvancePx = 0.0;
    for (final rune in spec.characters.runes) {
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(rune),
          style: _style(spec, sizePx, sigmaPx),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painters[rune] = painter;
      if (rune >= 0x30 && rune <= 0x39) {
        digitAdvancePx = math.max(digitAdvancePx, painter.width);
      }
    }

    final aboveTallest = (_aboveEm * sizePx).ceil();
    final cellHeightPx = aboveTallest + (_belowEm * sizePx).ceil() + 2 * pad;
    final baselinePx = pad + aboveTallest;

    // Shelf packing: cells left to right, a new row when the width runs out.
    final placed = <int, _Cell>{};
    var x = 0;
    var y = 0;
    var usedWidth = 0;
    for (final entry in painters.entries) {
      final isDigit = entry.key >= 0x30 && entry.key <= 0x39;
      final advance = isDigit ? digitAdvancePx : entry.value.width;
      final cellWidth = advance.ceil() + 2 * pad;
      if (x + cellWidth > _maxWidth && x > 0) {
        x = 0;
        y += cellHeightPx;
      }
      placed[entry.key] = _Cell(x, y, cellWidth, advance);
      x += cellWidth;
      usedWidth = math.max(usedWidth, x);
    }
    final width = math.max(1, usedWidth);
    final height = y + cellHeightPx;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (final entry in painters.entries) {
      final cell = placed[entry.key]!;
      final painter = entry.value;
      final isDigit = entry.key >= 0x30 && entry.key <= 0x39;
      final advance = isDigit ? digitAdvancePx : painter.width;
      // Centre a glyph in its advance, which matters for a digit narrower than
      // the tabular width.
      final inset = (advance - painter.width) / 2;
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      painter.paint(
        canvas,
        ui.Offset(cell.x + pad + inset, cell.y + baselinePx - baseline),
      );
    }
    final image = recorder.endRecording().toImageSync(width, height);

    final glyphs = <int, Glyph>{
      for (final entry in placed.entries)
        entry.key: Glyph(
          code: entry.key,
          left: entry.value.x.toDouble(),
          top: entry.value.y.toDouble(),
          right: (entry.value.x + entry.value.width).toDouble(),
          bottom: (entry.value.y + cellHeightPx).toDouble(),
          advance: entry.value.advance * scale,
        ),
    };
    for (final painter in painters.values) {
      painter.dispose();
    }

    return GlyphAtlas._(
      spec: spec,
      image: image,
      scale: scale,
      glyphs: glyphs,
      digitAdvance: digitAdvancePx * scale,
      padding: pad * scale,
      baseline: baselinePx * scale,
      cellHeight: cellHeightPx * scale,
    );
  }

  static TextStyle _style(GlyphAtlasSpec spec, double sizePx, double sigmaPx) {
    final base = TapeType.numeral(
      size: sizePx,
      weight: spec.weight,
      width: spec.width,
    );
    final paint = Paint()..color = TapeColors.spriteWhite;
    if (sigmaPx > 0) {
      paint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigmaPx);
    }
    return base.copyWith(foreground: paint);
  }

  /// The glyph for a code point, or null if the atlas has none.
  Glyph? glyph(int code) => glyphs[code];

  /// The glyph of the digit [d], 0 to 9.
  Glyph digit(int d) => glyphs[0x30 + d]!;

  /// The width in logical pixels of a sprite of [glyph], padding included.
  double spriteWidth(Glyph glyph) => (glyph.right - glyph.left) * scale;

  /// Whether the atlas has been disposed.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}

class _Cell {
  const _Cell(this.x, this.y, this.width, this.advance);

  final int x;
  final int y;
  final int width;
  final double advance;
}

/// Atlases already built, by spec. Making one lays out the text and rasterises
/// it, which is done once per size, weight and density, never per frame.
class GlyphAtlasCache {
  GlyphAtlasCache({this.capacity = 24});

  /// How many atlases to keep. The least recently used is disposed beyond it.
  final int capacity;

  final Map<GlyphAtlasSpec, GlyphAtlas> _atlases = {};

  int get length => _atlases.length;

  /// The atlas for [spec], built if it is not there.
  GlyphAtlas get(GlyphAtlasSpec spec) {
    final existing = _atlases.remove(spec);
    if (existing != null && !existing.isDisposed) {
      _atlases[spec] = existing; // most recently used goes last
      return existing;
    }
    final atlas = GlyphAtlas.build(spec);
    _atlases[spec] = atlas;
    while (_atlases.length > capacity) {
      final oldest = _atlases.keys.first;
      _atlases.remove(oldest)!.dispose();
    }
    return atlas;
  }

  /// Disposes every atlas, for a change of density.
  void clear() {
    for (final atlas in _atlases.values) {
      atlas.dispose();
    }
    _atlases.clear();
  }
}
