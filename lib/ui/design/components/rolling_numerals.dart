import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../motion/numeral_source.dart';
import '../motion/odometer.dart';
import '../render/glyph_atlas.dart';
import '../render/pixel.dart';
import '../render/render_kit.dart';
import '../render/sprite_batch.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/glow.dart';
import '../tokens/typography.dart';

/// How digits are grouped in a number (DESIGN.md 10): Indian for money
/// (₹1,23,456), and the western thousands where the app shows counts.
enum DigitGrouping {
  none,
  indian,
  western;

  /// Whether a separator sits between digit [i] and the one to its right, where
  /// digit 0 is the units digit.
  bool separatorAfter(int i) => switch (this) {
    none => false,
    western => i > 0 && i % 3 == 0,
    indian => i >= 3 && (i - 3).isEven,
  };
}

/// The box a readout reserves for its number (DESIGN.md 4.5): how many integer
/// digits, how many decimals, how they are grouped.
@immutable
class NumeralFormat {
  const NumeralFormat({
    required this.integerDigits,
    this.decimals = 0,
    this.grouping = DigitGrouping.none,
    this.signed = false,
  });

  /// The most integer digits shown. A larger value shows nines.
  final int integerDigits;

  /// The digits after the decimal point. The last is the ones column of the roll.
  final int decimals;

  final DigitGrouping grouping;

  /// Whether a negative value is shown with a minus sign (U+2212).
  final bool signed;

  @override
  bool operator ==(Object other) =>
      other is NumeralFormat &&
      other.integerDigits == integerDigits &&
      other.decimals == decimals &&
      other.grouping == grouping &&
      other.signed == signed;

  @override
  int get hashCode => Object.hash(integerDigits, decimals, grouping, signed);
}

/// Which colour a numeral is drawn in: a role, resolved against the theme, so that
/// Daylight and Night can change it (DESIGN.md 4.3 and 4.4).
enum NumeralRole {
  /// Live primary data: the livery's accent.
  accent,

  /// Primary values that are not in the accent.
  bright,

  /// Secondary values.
  mid,

  /// Anything that should recede.
  dim,

  /// Money: champagne.
  money,

  /// Needs attention.
  caution,

  /// Act now.
  critical;

  Color colorIn(TapePalette palette) => switch (this) {
    accent => palette.numeral,
    bright => palette.inkBright,
    mid => palette.inkMid,
    dim => palette.inkDim,
    money => palette.money,
    caution => palette.caution,
    critical => palette.critical,
  };

  /// The colour of its halo.
  Color glowIn(TapePalette palette) => switch (this) {
    accent || bright || mid || dim => palette.accentGlow,
    money => palette.moneyGlow,
    caution => palette.caution,
    critical => palette.critical,
  };
}

/// The measurements of a rolling readout at a font size, for laying out what is
/// around it.
class NumeralMetrics {
  const NumeralMetrics(this.size);

  /// The font size, in logical pixels.
  final double size;

  /// How far apart the digits of a rolling column are.
  double get pitch => TapeType.digitPitchEm * size;

  /// The height of a digit's ink.
  double get inkHeight => TapeType.digitHeightEm * size;

  /// The height of the readout's box: two pitches, so that a digit rolling out
  /// of the window is still inside it, since nothing is clipped.
  double get boxHeight => 2 * pitch;

  /// The baseline, from the top of the box: digits are centred in it.
  double get baseline =>
      boxHeight / 2 + TapeType.digitAboveBaselineEm * size / 2;

  /// The distance from the top of the box to the top of the digits' ink.
  double get inkTop => baseline - TapeType.digitAboveBaselineEm * size;
}

/// Numerals that roll like a precision mechanism (DESIGN.md 6.1).
///
/// The readout reads [source] and repaints from it: it never rebuilds for data.
/// It draws from a glyph atlas with the detented odometer behaviour of DESIGN.md
/// 5.6, in a fixed box anchored on the ones column, so the digits never move
/// sideways whatever the value.
///
/// The box is [NumeralMetrics.boxHeight] tall and its baseline is the digits'
/// baseline, so it can sit in a `Row` with `CrossAxisAlignment.baseline`.
class RollingNumerals extends LeafRenderObjectWidget {
  const RollingNumerals({
    super.key,
    required this.source,
    required this.format,
    required this.size,
    this.role = NumeralRole.accent,
    this.halo = 0,
  });

  final NumeralSource source;
  final NumeralFormat format;

  /// The font size, in logical pixels.
  final double size;

  final NumeralRole role;

  /// How strong the halo is, 0 to 1: 0 for none, [TapeGlow.heroHalo] for a hero
  /// readout. Daylight turns it off and Night halves it, whatever is asked
  /// (DESIGN.md 4.4).
  final double halo;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final render = RenderRollingNumerals();
    _configure(context, render);
    return render;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRollingNumerals renderObject,
  ) => _configure(context, renderObject);

  void _configure(BuildContext context, RenderRollingNumerals render) {
    final theme = TapeTheme.of(context);
    final kit = TapeRenderScope.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final palette = theme.palette;

    final atlas = kit.atlases.get(
      GlyphAtlasSpec(
        sizeLp: size,
        devicePixelRatio: dpr,
        weight: theme.livery.numeralWeight,
      ),
    );
    final strength = halo * palette.haloScale;
    GlyphAtlas? glow;
    if (strength > 0) {
      glow = kit.atlases.get(
        GlyphAtlasSpec(
          sizeLp: size,
          devicePixelRatio: dpr,
          weight: theme.livery.numeralWeight,
          glowSigmaLp: size * TapeGlow.numeralSigmaEm,
          resolution: theme.profile.halosAtHalfResolution
              ? TapeGlow.liteResolution
              : 1,
        ),
      );
    }

    render
      ..source = source
      ..format = format
      ..metrics = NumeralMetrics(size)
      ..atlas = atlas
      ..glowAtlas = glow
      ..haloStrength = strength
      ..color = role.colorIn(palette)
      ..staleColor = palette.stale
      ..glowColor = role.glowIn(palette)
      ..devicePixelRatio = dpr;
  }
}

/// The render object of [RollingNumerals]: layout of the slots, and a paint that
/// allocates nothing.
class RenderRollingNumerals extends RenderBox {
  NumeralSource? _source;
  NumeralFormat _format = const NumeralFormat(integerDigits: 1);
  NumeralMetrics _metrics = const NumeralMetrics(16);
  GlyphAtlas? _atlas;
  GlyphAtlas? _glowAtlas;
  double _haloStrength = 0;
  int _color = 0xFFFFFFFF;
  int _staleColor = 0xFF7A838F;
  int _glowColor = 0xFFFFFFFF;
  double _devicePixelRatio = 1;

  OdometerLayout? _layout;
  SpriteBatch? _core;
  SpriteBatch? _halo;
  final ui.Paint _corePaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false;
  final ui.Paint _haloPaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false
    ..blendMode = ui.BlendMode.plus;

  // The slots, in logical pixels from the left of the box, made when the atlas
  // or the format changes.
  Float64List _digitX = Float64List(0);
  Float64List _separatorX = Float64List(0);
  double _dotX = 0;
  double _width = 0;
  bool _slotsStale = true;

  set source(NumeralSource value) {
    if (identical(_source, value)) return;
    if (attached) _source?.removeListener(markNeedsPaint);
    _source = value;
    if (attached) value.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set format(NumeralFormat value) {
    if (_format == value) return;
    _format = value;
    _layout = null;
    _slotsStale = true;
    markNeedsLayout();
  }

  set metrics(NumeralMetrics value) {
    if (_metrics.size == value.size) return;
    _metrics = value;
    _slotsStale = true;
    markNeedsLayout();
  }

  set atlas(GlyphAtlas value) {
    if (identical(_atlas, value)) return;
    _atlas = value;
    _slotsStale = true;
    markNeedsLayout();
  }

  set glowAtlas(GlyphAtlas? value) {
    if (identical(_glowAtlas, value)) return;
    _glowAtlas = value;
    markNeedsPaint();
  }

  set haloStrength(double value) {
    if (_haloStrength == value) return;
    _haloStrength = value;
    markNeedsPaint();
  }

  set color(Color value) {
    final argb = value.toARGB32();
    if (_color == argb) return;
    _color = argb;
    markNeedsPaint();
  }

  set staleColor(Color value) {
    final argb = value.toARGB32();
    if (_staleColor == argb) return;
    _staleColor = argb;
    markNeedsPaint();
  }

  set glowColor(Color value) {
    final argb = value.toARGB32();
    if (_glowColor == argb) return;
    _glowColor = argb;
    markNeedsPaint();
  }

  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _source?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _source?.removeListener(markNeedsPaint);
    super.detach();
  }

  /// The pen position of the digit column [k] (0 is the ones column), from the
  /// left of the box. The ones column's position depends only on the format and
  /// the atlas, never on the value.
  @visibleForTesting
  double columnX(int k) {
    _ensureSlots();
    return _digitX[k];
  }

  /// The pen position of the group separator after digit [i] (0 is the units
  /// digit), from the left of the box.
  @visibleForTesting
  double separatorX(int i) {
    _ensureSlots();
    return _separatorX[i];
  }

  /// How strong the halo is, after the theme's rules.
  @visibleForTesting
  double get haloStrength => _haloStrength;

  /// Whether a halo atlas is in use.
  @visibleForTesting
  bool get hasHalo => _glowAtlas != null && _haloStrength > 0;

  void _ensureSlots() {
    if (!_slotsStale) return;
    final atlas = _atlas;
    if (atlas == null) return;
    final format = _format;
    final columns = format.integerDigits + format.decimals;
    _digitX = Float64List(columns);
    final separators = <int>[
      for (var i = format.integerDigits - 1; i > 0; i--)
        if (format.grouping.separatorAfter(i)) i,
    ];
    _separatorX = Float64List(format.integerDigits);
    final comma = atlas.glyph(0x2C)?.advance ?? 0;
    final dot = atlas.glyph(0x2E)?.advance ?? 0;

    var x = 0.0;
    for (var i = format.integerDigits - 1; i >= 0; i--) {
      _digitX[format.decimals + i] = x;
      x += atlas.digitAdvance;
      if (separators.contains(i)) {
        _separatorX[i] = x;
        x += comma;
      }
    }
    if (format.decimals > 0) {
      _dotX = x;
      x += dot;
      for (var j = format.decimals - 1; j >= 0; j--) {
        _digitX[j] = x;
        x += atlas.digitAdvance;
      }
    }
    _width = x;

    _layout = OdometerLayout(
      integerDigits: format.integerDigits,
      decimals: format.decimals,
    );
    final capacity = 2 * columns + format.integerDigits + 3;
    _core = SpriteBatch(capacity);
    _halo = SpriteBatch(capacity);
    _slotsStale = false;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _ensureSlots();
    return _width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _ensureSlots();
    return _width;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _metrics.boxHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => _metrics.boxHeight;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _ensureSlots();
    return constraints.constrain(Size(_width, _metrics.boxHeight));
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => baseline == TextBaseline.alphabetic ? _metrics.baseline : null;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      baseline == TextBaseline.alphabetic ? _metrics.baseline : null;

  @override
  void performLayout() {
    _ensureSlots();
    size = constraints.constrain(Size(_width, _metrics.boxHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = _source;
    final atlas = _atlas;
    final layout = _layout;
    final core = _core;
    if (source == null ||
        atlas == null ||
        layout == null ||
        core == null ||
        !source.hasValue) {
      return;
    }

    final value = source.value;
    layout.layout(value);
    final negative = _format.signed && value < 0;
    final pitch = _metrics.pitch;
    final dpr = _devicePixelRatio;
    final baselineY = offset.dy + _metrics.baseline;
    final color = _lerpRgb(_color, _staleColor, source.staleness);
    final glowAtlas = _glowAtlas;
    final halo = glowAtlas != null && _haloStrength > 0 ? _halo : null;
    final glowRgb = _lerpRgb(_glowColor, _staleColor, source.staleness);
    final canvas = context.canvas;
    final columns = _format.integerDigits + _format.decimals;

    for (var i = 0; i < layout.count; i++) {
      final k = layout.column[i];
      final dy = layout.offset[i] * pitch;
      final alpha = layout.alpha[i];
      final digit = layout.digit[i];
      _put(
        atlas,
        core,
        atlas.digit(digit),
        offset.dx,
        baselineY,
        dpr,
        _digitX[k],
        dy,
        color,
        alpha,
      );
      if (halo != null) {
        _put(
          glowAtlas!,
          halo,
          glowAtlas.digit(digit),
          offset.dx,
          baselineY,
          dpr,
          _digitX[k],
          dy,
          glowRgb,
          alpha * _haloStrength,
        );
      }
    }

    // Separators appear with the digit to their left.
    for (var i = _format.integerDigits - 1; i > 0; i--) {
      if (!_format.grouping.separatorAfter(i)) continue;
      final alpha = layout.presence(_format.decimals + i);
      if (alpha <= 0) continue;
      final glyph = atlas.glyph(0x2C);
      if (glyph == null) continue;
      _put(
        atlas,
        core,
        glyph,
        offset.dx,
        baselineY,
        dpr,
        _separatorX[i],
        0,
        color,
        alpha,
      );
      if (halo != null) {
        _put(
          glowAtlas!,
          halo,
          glowAtlas.glyph(0x2C)!,
          offset.dx,
          baselineY,
          dpr,
          _separatorX[i],
          0,
          glowRgb,
          alpha * _haloStrength,
        );
      }
    }

    if (_format.decimals > 0) {
      final glyph = atlas.glyph(0x2E);
      if (glyph != null) {
        _put(atlas, core, glyph, offset.dx, baselineY, dpr, _dotX, 0, color, 1);
        if (halo != null) {
          _put(
            glowAtlas!,
            halo,
            glowAtlas.glyph(0x2E)!,
            offset.dx,
            baselineY,
            dpr,
            _dotX,
            0,
            glowRgb,
            _haloStrength,
          );
        }
      }
    }

    if (negative) {
      final minus = atlas.glyph(0x2212);
      if (minus != null) {
        // Against the leftmost digit that is showing.
        var k = columns - 1;
        while (k > _format.decimals && layout.presence(k) <= 0) {
          k--;
        }
        final penX = _digitX[k] - minus.advance;
        _put(atlas, core, minus, offset.dx, baselineY, dpr, penX, 0, color, 1);
        if (halo != null) {
          _put(
            glowAtlas!,
            halo,
            glowAtlas.glyph(0x2212)!,
            offset.dx,
            baselineY,
            dpr,
            penX,
            0,
            glowRgb,
            _haloStrength,
          );
        }
      }
    }

    if (halo != null) halo.draw(canvas, glowAtlas!.image, _haloPaint);
    core.draw(canvas, atlas.image, _corePaint);
  }

  /// Adds one glyph to [batch]. The pen is at [penX] from the box's left edge
  /// [boxX], on [baselineY], moved [dy] down; its sprite is placed by the atlas's
  /// own padding and baseline. A glyph at rest sits on whole physical pixels, and
  /// one that is rolling moves smoothly between them.
  void _put(
    GlyphAtlas atlas,
    SpriteBatch batch,
    Glyph glyph,
    double boxX,
    double baselineY,
    double dpr,
    double penX,
    double dy,
    int rgb,
    double alpha,
  ) {
    final x = Pixel.snap(boxX + penX, dpr) - atlas.padding;
    var y = baselineY + dy;
    if (dy == 0) y = Pixel.snap(y, dpr);
    batch.add(
      left: glyph.left,
      top: glyph.top,
      right: glyph.right,
      bottom: glyph.bottom,
      x: x,
      y: y - atlas.baseline,
      scale: atlas.scale,
      color: SpriteBatch.tint(rgb, alpha),
    );
  }

  /// [a] moved [t] of the way to [b], both opaque ARGB, as an RGB int.
  static int _lerpRgb(int a, int b, double t) {
    if (t <= 0) return a & 0xFFFFFF;
    if (t >= 1) return b & 0xFFFFFF;
    int channel(int shift) {
      final from = (a >> shift) & 0xFF;
      final to = (b >> shift) & 0xFF;
      return (from + (to - from) * t).round();
    }

    return (channel(16) << 16) | (channel(8) << 8) | channel(0);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<NumeralFormat>('format', _format));
    properties.add(DoubleProperty('haloStrength', _haloStrength));
    properties.add(IntProperty('digits', math.max(0, _format.integerDigits)));
  }
}
