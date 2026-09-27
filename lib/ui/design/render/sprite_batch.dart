import 'dart:typed_data';
import 'dart:ui' as ui;

/// A reusable batch of sprites for one `Canvas.drawRawAtlas` call (DESIGN.md 9.3).
///
/// The buffers are made once and refilled every frame, so drawing a readout
/// allocates nothing. Sprites are placed with [add]; [draw] draws them all and
/// [clear]s the batch. Slots not used by this frame are made empty, since
/// `drawRawAtlas` draws every slot the lists hold.
class SpriteBatch {
  SpriteBatch(this.capacity)
    : _transforms = Float32List(capacity * 4),
      _rects = Float32List(capacity * 4),
      _colors = Int32List(capacity);

  final int capacity;
  final Float32List _transforms;
  final Float32List _rects;
  final Int32List _colors;

  int _count = 0;

  /// How many sprites are in the batch.
  int get count => _count;

  /// Adds a sprite: the atlas rectangle [left], [top], [right], [bottom] (in
  /// atlas pixels), drawn with its top-left corner at [x], [y] (logical pixels),
  /// scaled by [scale] (logical pixels per atlas pixel), tinted with [color]
  /// (ARGB). Beyond [capacity] a sprite is dropped.
  void add({
    required double left,
    required double top,
    required double right,
    required double bottom,
    required double x,
    required double y,
    required double scale,
    required int color,
  }) {
    if (_count >= capacity) return;
    final t = _count * 4;
    _transforms[t] = scale;
    _transforms[t + 1] = 0;
    _transforms[t + 2] = x;
    _transforms[t + 3] = y;
    _rects[t] = left;
    _rects[t + 1] = top;
    _rects[t + 2] = right;
    _rects[t + 3] = bottom;
    _colors[_count] = color;
    _count++;
  }

  /// Draws the batch from [atlas] and empties it.
  ///
  /// The sprites are tinted by their colours with `BlendMode.modulate`, so a
  /// white atlas takes on the colour and the alpha of each sprite. [paint] says
  /// how the result meets the canvas: `BlendMode.plus` for a halo. A low filter
  /// quality keeps a rolling digit smooth between pixels.
  void draw(ui.Canvas canvas, ui.Image atlas, ui.Paint paint) {
    // Empty the slots this frame did not fill.
    for (var i = _count; i < capacity; i++) {
      final t = i * 4;
      _rects[t] = 0;
      _rects[t + 1] = 0;
      _rects[t + 2] = 0;
      _rects[t + 3] = 0;
    }
    canvas.drawRawAtlas(
      atlas,
      _transforms,
      _rects,
      _colors,
      ui.BlendMode.modulate,
      null,
      paint,
    );
    _count = 0;
  }

  void clear() => _count = 0;

  /// An ARGB colour that is white with the given [alpha], 0 to 1: the tint of a
  /// sprite that keeps its atlas colour and only fades.
  static int white(double alpha) => tint(0xFFFFFF, alpha);

  /// [rgb] (0xRRGGBB) at [alpha], 0 to 1, as an ARGB int.
  static int tint(int rgb, double alpha) {
    final a = (alpha.clamp(0.0, 1.0) * 255).round();
    return (a << 24) | (rgb & 0xFFFFFF);
  }

  /// [color] with its alpha multiplied by [alpha], as an ARGB int.
  static int fromColor(ui.Color color, double alpha) {
    final a = (color.a * alpha.clamp(0.0, 1.0) * 255).round();
    final rgb =
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();
    return (a << 24) | rgb;
  }
}
