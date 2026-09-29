import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../motion/motion_clock.dart';
import '../motion/motion_scope.dart';
import '../motion/numeral_source.dart';
import '../motion/phosphor.dart';
import '../render/pixel.dart';
import '../render/render_kit.dart';
import '../render/seven_segment.dart';
import '../render/sprite_batch.dart';
import '../theme/tape_theme.dart';
import '../tokens/glow.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';
import 'numeral_format.dart';

/// Numerals in the seven-segment renderer of the VFD livery (DESIGN.md 6.1 and
/// 6.17): chamfered segments with an 8 degree lean, ghost segments at 7% for the
/// ones that are off, and phosphor on every segment, so a change of digit
/// crossfades segment by segment like a real vacuum-fluorescent display.
///
/// It does not roll: a VFD does not scroll its digits, it lights the segments of
/// the next one. Leading zeros are dark, and show their ghost segments, which is
/// the ghost 8 of DESIGN.md 4.5.
class SevenSegmentNumerals extends LeafRenderObjectWidget {
  const SevenSegmentNumerals({
    super.key,
    required this.source,
    required this.format,
    required this.size,
    this.role = NumeralRole.accent,
    this.halo = 0,
    this.presence,
  });

  final NumeralSource source;
  final NumeralFormat format;

  /// The font size the readout is set at: its digits are as tall as Saira's at
  /// this size, so the two faces share a box.
  final double size;

  final NumeralRole role;
  final double halo;

  /// 1 is fully present and 0 is fully gone.
  final ValueListenable<double>? presence;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final render = RenderSevenSegmentNumerals(motion: MotionScope.of(context));
    _configure(context, render);
    return render;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSevenSegmentNumerals renderObject,
  ) => _configure(context, renderObject);

  void _configure(BuildContext context, RenderSevenSegmentNumerals render) {
    final theme = TapeTheme.of(context);
    final kit = TapeRenderScope.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final palette = theme.palette;
    final digitHeight = TapeType.digitHeightEm * size;

    final atlas = kit.segments(heightLp: digitHeight, devicePixelRatio: dpr);
    final strength = halo * palette.haloScale;
    SevenSegmentAtlas? glow;
    if (strength > 0) {
      glow = kit.segments(
        heightLp: digitHeight,
        devicePixelRatio: dpr,
        glowSigmaLp: size * TapeGlow.numeralSigmaEm,
        resolution: theme.profile.halosAtHalfResolution
            ? TapeGlow.liteResolution
            : 1,
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
      ..ghostAlpha = theme.livery.ghostAlpha
      ..devicePixelRatio = dpr
      ..presence = presence;
  }
}

/// The render object of [SevenSegmentNumerals].
class RenderSevenSegmentNumerals extends RenderBox {
  RenderSevenSegmentNumerals({required this.motion});

  final MotionClock motion;

  NumeralSource? _source;
  NumeralFormat _format = const NumeralFormat(integerDigits: 1);
  NumeralMetrics _metrics = const NumeralMetrics(16);
  SevenSegmentAtlas? _atlas;
  SevenSegmentAtlas? _glowAtlas;
  double _haloStrength = 0;
  int _color = 0xFFFFFFFF;
  int _staleColor = 0xFF7A838F;
  int _glowColor = 0xFFFFFFFF;
  double _ghostAlpha = 0.07;
  double _devicePixelRatio = 1;
  ValueListenable<double>? _presence;
  double _alphaMul = 1;

  PhosphorBank? _bank;
  SpriteBatch? _core;
  SpriteBatch? _halo;
  List<int> _masks = const [];
  final ui.Paint _corePaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false;
  final ui.Paint _haloPaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false
    ..blendMode = ui.BlendMode.plus;

  Float64List _digitX = Float64List(0);
  Float64List _separatorX = Float64List(0);
  double _dotX = 0;
  double _width = 0;
  bool _slotsStale = true;

  set source(NumeralSource value) {
    if (identical(_source, value)) return;
    if (attached) _source?.removeListener(_onSource);
    _source = value;
    if (attached) {
      value.addListener(_onSource);
      _onSource();
    }
    markNeedsPaint();
  }

  set format(NumeralFormat value) {
    if (_format == value) return;
    _format = value;
    _slotsStale = true;
    markNeedsLayout();
  }

  set metrics(NumeralMetrics value) {
    if (_metrics.size == value.size) return;
    _metrics = value;
    _slotsStale = true;
    markNeedsLayout();
  }

  set atlas(SevenSegmentAtlas value) {
    if (identical(_atlas, value)) return;
    _atlas = value;
    _slotsStale = true;
    markNeedsLayout();
  }

  set glowAtlas(SevenSegmentAtlas? value) {
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

  set ghostAlpha(double value) {
    if (_ghostAlpha == value) return;
    _ghostAlpha = value;
    markNeedsPaint();
  }

  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  set presence(ValueListenable<double>? value) {
    if (identical(_presence, value)) return;
    if (attached) _presence?.removeListener(markNeedsPaint);
    _presence = value;
    if (attached) value?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// The current presence multiplier, for tests.
  @visibleForTesting
  double get presenceMul => (_presence?.value ?? 1).clamp(0.0, 1.0);

  @override
  bool get isRepaintBoundary => true;

  /// Which segments each column is lit with, for tests: a bit per [Segment].
  @visibleForTesting
  List<int> get masks => _masks;

  /// The current phosphor level of a segment of a column, for tests.
  @visibleForTesting
  double segmentLevel(int column, Segment segment) =>
      _bank?.levels[column * 7 + segment.index] ?? 0;

  @visibleForTesting
  double columnX(int k) {
    _ensureSlots();
    return _digitX[k];
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _source?.addListener(_onSource);
    _bank?.addListener(markNeedsPaint);
    _presence?.addListener(markNeedsPaint);
    _onSource();
  }

  @override
  void detach() {
    _source?.removeListener(_onSource);
    _bank?.removeListener(markNeedsPaint);
    _presence?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _bank?.dispose();
    _bank = null;
    super.dispose();
  }

  void _ensureSlots() {
    if (!_slotsStale) return;
    final atlas = _atlas;
    if (atlas == null) return;
    final format = _format;
    final columns = format.integerDigits + format.decimals;
    final geometry = atlas.geometry;
    final advance = geometry.advance;
    final narrow = geometry.thickness * 2.2;

    _digitX = Float64List(columns);
    _separatorX = Float64List(format.integerDigits);
    var x = 0.0;
    for (var i = format.integerDigits - 1; i >= 0; i--) {
      _digitX[format.decimals + i] = x;
      x += advance;
      if (i > 0 && format.grouping.separatorAfter(i)) {
        _separatorX[i] = x - geometry.thickness * 0.6;
        x += narrow;
      }
    }
    if (format.decimals > 0) {
      _dotX = x - geometry.thickness * 0.6;
      x += narrow;
      for (var j = format.decimals - 1; j >= 0; j--) {
        _digitX[j] = x;
        x += advance;
      }
    }
    _width = x - TapeShape.sevenSegmentSpacing * geometry.height;

    _bank?.removeListener(markNeedsPaint);
    _bank?.dispose();
    _bank = PhosphorBank(clock: motion, count: columns * 7);
    if (attached) _bank!.addListener(markNeedsPaint);
    _masks = List<int>.filled(columns, -1);
    final capacity = columns * 7 + format.integerDigits + 3;
    _core = SpriteBatch(capacity);
    _halo = SpriteBatch(capacity);
    _slotsStale = false;
    _onSource();
  }

  /// Sets each segment's target from the digits the source shows now.
  void _onSource() {
    final source = _source;
    final bank = _bank;
    if (source == null || bank == null || !source.hasValue) {
      markNeedsPaint();
      return;
    }
    final format = _format;
    final columns = format.integerDigits + format.decimals;
    final scale = math.pow(10, format.decimals).toDouble();
    final max = math.pow(10, columns).toDouble() - 1;
    var scaled = source.value.isNaN ? 0.0 : source.value.abs() * scale;
    if (scaled > max) scaled = max;
    final n = scaled.round();
    var divisor = 1;
    for (var k = 0; k < columns; k++) {
      final leadingZero = k > format.decimals && n < divisor;
      final mask = leadingZero
          ? SegmentMask.blank
          : SegmentMask.digit((n ~/ divisor) % 10);
      divisor *= 10;
      if (_masks[k] != mask) {
        _masks[k] = mask;
        for (final segment in Segment.values) {
          bank.setTarget(
            k * 7 + segment.index,
            SegmentMask.lit(mask, segment) ? 1 : 0,
          );
        }
      }
    }
    markNeedsPaint();
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
    final bank = _bank;
    final core = _core;
    if (source == null ||
        atlas == null ||
        bank == null ||
        core == null ||
        !source.hasValue) {
      return;
    }
    _alphaMul = (_presence?.value ?? 1).clamp(0.0, 1.0);
    if (_alphaMul <= 0.001) return;
    final format = _format;
    final columns = format.integerDigits + format.decimals;
    final glow = _glowAtlas;
    final halo = glow != null && _haloStrength > 0 ? _halo : null;
    final color = _lerpRgb(_color, _staleColor, source.staleness);
    final glowRgb = _lerpRgb(_glowColor, _staleColor, source.staleness);
    final dpr = _devicePixelRatio;
    // A digit's bottom edge is on the baseline.
    final bottom = Pixel.snap(offset.dy + _metrics.baseline, dpr);
    final top = bottom - atlas.height;

    for (var k = 0; k < columns; k++) {
      final x = Pixel.snap(offset.dx + _digitX[k], dpr);
      for (final segment in Segment.values) {
        final level = bank.levels[k * 7 + segment.index];
        final alpha = (_ghostAlpha + (1 - _ghostAlpha) * level) * _alphaMul;
        final rect = atlas.sprites[segment.index];
        core.add(
          left: rect.left,
          top: rect.top,
          right: rect.right,
          bottom: rect.bottom,
          x: x - atlas.padding,
          y: top - atlas.padding,
          scale: atlas.scale,
          color: SpriteBatch.tint(color, alpha),
        );
        if (halo != null && level > 0.01) {
          final g = glow!.sprites[segment.index];
          halo.add(
            left: g.left,
            top: g.top,
            right: g.right,
            bottom: g.bottom,
            x: x - glow.padding,
            y: top - glow.padding,
            scale: glow.scale,
            color: SpriteBatch.tint(glowRgb, level * _haloStrength * _alphaMul),
          );
        }
      }
    }

    // The decimal point and the group separators: dots that are lit while their
    // digit shows.
    if (format.decimals > 0) {
      _mark(
        atlas,
        core,
        SevenSegmentAtlas.pointSprite,
        offset.dx,
        _dotX,
        top,
        dpr,
        color,
        _alphaMul,
      );
      if (halo != null) {
        _mark(
          glow!,
          halo,
          SevenSegmentAtlas.pointSprite,
          offset.dx,
          _dotX,
          top,
          dpr,
          glowRgb,
          _haloStrength * _alphaMul,
        );
      }
    }
    for (var i = format.integerDigits - 1; i > 0; i--) {
      if (!format.grouping.separatorAfter(i)) continue;
      final column = format.decimals + i;
      final lit = _masks[column] != SegmentMask.blank
          ? 1.0
          : bank.levels[column * 7 + Segment.a.index];
      _mark(
        atlas,
        core,
        SevenSegmentAtlas.commaSprite,
        offset.dx,
        _separatorX[i],
        top,
        dpr,
        color,
        math.max(_ghostAlpha, lit) * _alphaMul,
      );
      if (halo != null && lit > 0.01) {
        _mark(
          glow!,
          halo,
          SevenSegmentAtlas.commaSprite,
          offset.dx,
          _separatorX[i],
          top,
          dpr,
          glowRgb,
          lit * _haloStrength * _alphaMul,
        );
      }
    }

    if (halo != null) halo.draw(context.canvas, glow!.image, _haloPaint);
    core.draw(context.canvas, atlas.image, _corePaint);
  }

  /// Adds a dot sprite (the point or a comma) to [batch].
  void _mark(
    SevenSegmentAtlas atlas,
    SpriteBatch batch,
    int sprite,
    double boxX,
    double penX,
    double top,
    double dpr,
    int rgb,
    double alpha,
  ) {
    final rect = atlas.sprites[sprite];
    batch.add(
      left: rect.left,
      top: rect.top,
      right: rect.right,
      bottom: rect.bottom,
      x: Pixel.snap(boxX + penX, dpr) - atlas.padding,
      y: top - atlas.padding,
      scale: atlas.scale,
      color: SpriteBatch.tint(rgb, alpha),
    );
  }

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
}
