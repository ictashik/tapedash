import 'dart:math' as math;
import 'dart:ui' as ui;

import '../tokens/colors.dart';

/// What a glow sprite is the halo of.
enum GlowShape {
  /// A soft round spot: a puck, a dot, a touch.
  disc,

  /// A rounded bar: a needle blade, a segment, a horizon line.
  bar,
}

/// The shape, size and blur of a halo sprite, without its colour.
class GlowSpec {
  const GlowSpec({
    required this.shape,
    required this.width,
    required this.height,
    required this.sigma,
    this.devicePixelRatio = 1,
    this.resolution = 1,
  });

  final GlowShape shape;

  /// The size of the core shape the halo surrounds, in logical pixels. The sprite
  /// is larger, by the blur.
  final double width;
  final double height;

  /// The blur, in logical pixels.
  final double sigma;

  final double devicePixelRatio;

  /// 0.5 for the half-resolution halos of Tier 1 (DESIGN.md 9.1).
  final double resolution;

  @override
  bool operator ==(Object other) =>
      other is GlowSpec &&
      other.shape == shape &&
      other.width == width &&
      other.height == height &&
      other.sigma == sigma &&
      other.devicePixelRatio == devicePixelRatio &&
      other.resolution == resolution;

  @override
  int get hashCode =>
      Object.hash(shape, width, height, sigma, devicePixelRatio, resolution);
}

/// A halo, pre-rendered (DESIGN.md 4.9). White on transparent: the colour and the
/// strength are set when it is drawn, with `BlendMode.plus`.
class GlowSprite {
  GlowSprite._({
    required this.image,
    required this.scale,
    required this.margin,
    required this.spec,
  });

  final ui.Image image;

  /// Logical pixels per image pixel.
  final double scale;

  /// How far the halo extends past the core shape, on every side, in logical
  /// pixels.
  final double margin;

  final GlowSpec spec;

  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// The sprite's size in logical pixels: the core shape and the margin round it.
  ui.Size get size => ui.Size(image.width * scale, image.height * scale);

  /// Draws the sprite so that its core shape's top-left is at [x], [y]: the halo
  /// reaches [margin] beyond that. [color] tints it, and its alpha is the
  /// strength. It composites with `BlendMode.plus`, which only adds light.
  void draw(
    ui.Canvas canvas,
    double x,
    double y,
    ui.Color color,
    ui.Paint paint,
  ) {
    paint.color = color;
    canvas.save();
    canvas.translate(x - margin, y - margin);
    canvas.scale(scale);
    canvas.drawImage(image, ui.Offset.zero, paint);
    canvas.restore();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}

/// Glow sprites, made once and reused (DESIGN.md 9.3).
///
/// Each is a blurred white shape rendered into an image with `MaskFilter.blur`,
/// so no blur is ever computed while a frame is painted. Sprites are rebuilt only
/// when a size or the screen density changes, and never when a livery does: the
/// colour is applied at draw time.
class GlowCache {
  GlowCache({this.capacity = 32});

  final int capacity;
  final Map<GlowSpec, GlowSprite> _sprites = {};

  int get length => _sprites.length;

  /// The sprite for [spec], made if it is not there.
  GlowSprite get(GlowSpec spec) {
    final existing = _sprites.remove(spec);
    if (existing != null && !existing.isDisposed) {
      _sprites[spec] = existing;
      return existing;
    }
    final sprite = _build(spec);
    _sprites[spec] = sprite;
    while (_sprites.length > capacity) {
      _sprites.remove(_sprites.keys.first)!.dispose();
    }
    return sprite;
  }

  void clear() {
    for (final sprite in _sprites.values) {
      sprite.dispose();
    }
    _sprites.clear();
  }

  static GlowSprite _build(GlowSpec spec) {
    final scale = 1 / (spec.devicePixelRatio * spec.resolution);
    final sigma = spec.sigma / scale;
    // Three sigma holds all but a sliver of a Gaussian's tail.
    final margin = (3 * sigma).ceil() + 1;
    final w = (spec.width / scale).ceil();
    final h = (spec.height / scale).ceil();
    final width = w + 2 * margin;
    final height = h + 2 * margin;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..color = TapeColors.spriteWhite
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
    final core = ui.Rect.fromLTWH(
      margin.toDouble(),
      margin.toDouble(),
      w.toDouble(),
      h.toDouble(),
    );
    switch (spec.shape) {
      case GlowShape.disc:
        canvas.drawOval(core, paint);
      case GlowShape.bar:
        final radius = math.min(core.width, core.height) / 2;
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(core, ui.Radius.circular(radius)),
          paint,
        );
    }
    final image = recorder.endRecording().toImageSync(width, height);
    return GlowSprite._(
      image: image,
      scale: scale,
      margin: margin * scale,
      spec: spec,
    );
  }
}
